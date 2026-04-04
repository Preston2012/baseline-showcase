// ========================================================================
// SUPABASE EDGE FUNCTION: generate-embedding (DEPLOY-READY v1.3.6)
// Deploy to: supabase/functions/generate-embedding/index.ts
// ========================================================================
// Changes from v1.3.5:
// - Inactive figure: DEFERRED + HTTP 409 (not ERROR + 400) - semantic correctness
// - MAX_TEXT_LENGTH raised from 8000 → 50000 (matches A1 statement cap)
// - Drift detection logs to pipeline_events (queryable, not just console)
// - Token count missing → logged in SUCCESS details
// - Kill switch startup log added
// - total_attempts added to response JSON
//
// NOTE: pipeline_events schema must be verified against A11 before deploy.
// Expected columns: statement_id, stage, event_type, details, created_at
// Expected event_types: START, SUCCESS, ERROR, DEFERRED, KILLSWITCH
//
// Guarantees:
// - Packet 01: GLOBAL compute KILLSWITCH halts before any AI call
// - Packet 05: embedding model is env-var selected, never hardcoded
// - Prevents double OpenAI charges via DB advisory lock RPC
// - Embeds DB text only (no poisoning / no caller drift)
// - MAX_TEXT_LENGTH + token-proxy cap (deny-of-wallet / timeout control)
// - Retry w/ jittered exponential backoff for transient failures
// - cost_log is best-effort + non-blocking but loud on failure
// - Re-checks statement after lock to avoid revocation/embedding races
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY =
Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const EMBED_AUTH_TOKEN = Deno.env.get("EMBED_AUTH_TOKEN") || "";
// Packet 05 (LOCKED): env-var model swap (NO silent fallback)
// Validated per-request, not at module level (top-level throw kills entire function)
const OPENAI_EMBED_MODEL_ENV = Deno.env.get("OPENAI_EMBED_MODEL") || "";
// Kill switch startup log (debugging aid)
const BASELINE_KILL_SWITCH_RAW = Deno.env.get("BASELINE_KILL_SWITCH") || "";
console.log("A4 generate-embedding startup", {
BASELINE_KILL_SWITCH: BASELINE_KILL_SWITCH_RAW || "(not set)",
OPENAI_EMBED_MODEL: OPENAI_EMBED_MODEL_ENV,
});
const OPENAI_TIMEOUT_MS = 30000;
const MIN_TEXT_LENGTH = 20;
const MAX_TEXT_LENGTH = 50000; // Matches A1 statement cap
// Token-proxy cap: simple word-count guard (cheap + deterministic)
const MAX_WORDS_PROXY = 10000; // Raised proportionally with MAX_TEXT_LENGTH
// Schema expects 1536 for V1.4 (locked in A1 statements.embedding vector(1536))
const EMBEDDING_DIM = 1536;
// Optional: cost per 1M tokens (do NOT hardcode pricing in code)
// Set OPENAI_EMBED_COST_PER_1M_TOKENS="0.02" etc.
const OPENAI_EMBED_COST_PER_1M_TOKENS = (() => {
const raw = Deno.env.get("OPENAI_EMBED_COST_PER_1M_TOKENS");
if (!raw) return null;
const n = Number(raw);
return Number.isFinite(n) && n >= 0 ? n : null;
})();
// Model->dimension map to fail-fast on misconfig BEFORE charging OpenAI
const MODEL_DIMENSION_MAP: Record<string, number> = {
"text-embedding-3-small": 1536,
"text-embedding-3-large": 3072,
"text-embedding-ada-002": 1536,
};
// If Supabase Edge exposes EdgeRuntime.waitUntil, use it; otherwise fallback
const waitUntil = (promise: Promise<unknown>) => {
const er = (globalThis as any).EdgeRuntime;
if (er && typeof er.waitUntil === "function") {
er.waitUntil(promise);
return;
}
promise.catch((e) => {
console.error("waitUntil fallback caught async error", { message: e?.message });
});
};
interface EmbeddingRequest {
statement_id: string;
figure_id: string;
text?: string; // ignored for embedding (DB text only); used for drift warning
}
// -------------------------- helpers --------------------------
const json = (status: number, payload: Record<string, unknown>) =>
new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json" },
});
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const isRetryableStatus = (status: number) =>
status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
const UUID_REGEX =
/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function jitteredBackoff(attempt: number) {
const base = 500 * 2 ** (attempt - 1); // 500, 1000, 2000
const jitter = Math.random() * 200; // 0..200ms
return base + jitter;
}
function parseKillswitch(): boolean {
const v = BASELINE_KILL_SWITCH_RAW.trim();
return v === "TRUE" || v.toLowerCase() === "true";
}
// -------------------------- pipeline_events logging (A11) --------------------------
// NOTE: Schema must match A11. Expected: statement_id, stage, event_type, details, created_at
async function logPipelineEvent(
supabase: any,
statementId: string,
eventType: "START" | "SUCCESS" | "ERROR" | "DEFERRED" | "KILLSWITCH",
details?: Record<string, unknown>
) {
try {
await supabase.from("pipeline_events").insert({
statement_id: statementId,
stage: "EMBEDDING",
event_type: eventType,
details: details || {},
// created_at: let DB default handle it
});
} catch (e) {
// Best-effort - don't fail the pipeline on logging errors
console.error("pipeline_events insert failed", { statementId, eventType, error: e });
}
}
async function fetchOpenAIEmbedding(modelUsed: string, inputText: string): Promise<{ data:
any; attempts: number }> {
// Fail fast if model dimension is known and incompatible with schema
const expectedDim = MODEL_DIMENSION_MAP[modelUsed];
if (!expectedDim) {
throw new Error(
`Unknown embedding model "${modelUsed}". Add to MODEL_DIMENSION_MAP to allow
preflight checks.`
);
}
if (expectedDim !== EMBEDDING_DIM) {
throw new Error(
`Model "${modelUsed}" returns ${expectedDim} dims but schema expects
${EMBEDDING_DIM}. Refuse before charging.`
);
}
const maxAttempts = 3;
for (let attempt = 1; attempt <= maxAttempts; attempt++) {
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);
try {
const res = await fetch("https://api.openai.com/v1/embeddings", {
method: "POST",
signal: controller.signal,
headers: {
"Content-Type": "application/json",
Authorization: `Bearer ${OPENAI_API_KEY}`,
},
body: JSON.stringify({
model: modelUsed,
input: inputText,
encoding_format: "float",
}),
});
if (!res.ok) {
const bodyText = await res.text().catch(() => "");
if (isRetryableStatus(res.status) && attempt < maxAttempts) {
await sleep(jitteredBackoff(attempt));
continue;
}
throw new Error(`OpenAI API error: ${res.status} ${bodyText}`);
}
const openaiData = await res.json();
const embedding: number[] | undefined = openaiData?.data?.[0]?.embedding;
if (!Array.isArray(embedding) || embedding.length !== EMBEDDING_DIM) {
throw new Error("Invalid embedding payload (missing or wrong dimension)");
}
return { data: openaiData, attempts: attempt };
} catch (e: any) {
const isAbort = e?.name === "AbortError";
const isNetworkish =
typeof e?.message === "string" &&
(e.message.includes("network") ||
e.message.includes("fetch") ||
e.message.includes("ECONN"));
if ((isAbort || isNetworkish) && attempt < maxAttempts) {
await sleep(jitteredBackoff(attempt));
continue;
}
throw e;
} finally {
clearTimeout(timeout);
}
}
throw new Error("OpenAI embedding failed after retries");
}
// ========================================================================
// handler
// ========================================================================
serve(async (req: Request) => {
const startedAt = Date.now();
let statement_id = "";
let figure_id = "";
let supabase: any = null;
// Per-invocation model lock (prevents "mixed model" across retries)
const modelUsed = OPENAI_EMBED_MODEL_ENV;
try {
// ------------------------------------------------------------------------
// Auth check (token gate)
// ------------------------------------------------------------------------
const authHeader = req.headers.get("Authorization");
if (!authHeader || authHeader !== `Bearer ${EMBED_AUTH_TOKEN}`) {
return json(401, { error: "Unauthorized" });
}
// ------------------------------------------------------------------------
// Parse + validation (before killswitch so we can log statement_id)
// ------------------------------------------------------------------------
let body: EmbeddingRequest;
try {
body = await req.json();
} catch {
return json(400, { error: "Invalid JSON body" });
}
statement_id = (body.statement_id || "").trim();
figure_id = (body.figure_id || "").trim();
if (!statement_id || !figure_id) {
return json(400, { error: "Missing statement_id or figure_id" });
}
if (!UUID_REGEX.test(statement_id)) {
return json(400, { error: "statement_id must be valid UUID" });
}
if (!UUID_REGEX.test(figure_id)) {
return json(400, { error: "figure_id must be valid UUID" });
}
supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
// ------------------------------------------------------------------------
// KILLSWITCH check (Packet 01: emergency compute halt)
// ------------------------------------------------------------------------
if (parseKillswitch()) {
console.warn("BASELINE_KILL_SWITCH active: compute halted", { statement_id });
waitUntil(logPipelineEvent(supabase, statement_id, "KILLSWITCH", {
reason: "BASELINE_KILL_SWITCH enabled",
}));
return json(503, { error: "Compute halted by killswitch", killswitch: true });
}
// ------------------------------------------------------------------------
// Log START
// ------------------------------------------------------------------------
waitUntil(logPipelineEvent(supabase, statement_id, "START", {
figure_id,
model: modelUsed,
}));
// ------------------------------------------------------------------------
// 1) Fetch statement (embed DB text only)
// ------------------------------------------------------------------------
const { data: stmt, error: stmtErr } = await supabase
.from("statements")
.select("statement_id, figure_id, text, embedding, baseline_delta, is_revoked")
.eq("statement_id", statement_id)
.single();
if (stmtErr || !stmt) {
console.error("Statement fetch failed", { statement_id, error: stmtErr?.message });
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Statement not found",
error: stmtErr?.message,
}));
return json(404, { error: "Statement not found" });
}
if (stmt.figure_id !== figure_id) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "figure_id mismatch",
}));
return json(409, { error: "figure_id does not match statement" });
}
// Idempotency early exit
if (stmt.embedding !== null) {
waitUntil(logPipelineEvent(supabase, statement_id, "DEFERRED", {
reason: "Already embedded",
}));
return json(200, {
statement_id,
already_embedded: true,
baseline_delta: stmt.baseline_delta,
model_used: modelUsed,
elapsed_ms: Date.now() - startedAt,
});
}
if (stmt.is_revoked === true) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Statement revoked",
}));
return json(409, { error: "Statement is revoked" });
}
// ------------------------------------------------------------------------
// Figure active check (skip compute for inactive figures)
// Semantic: this is a DEFERRAL, not an error
// ------------------------------------------------------------------------
const { data: fig, error: figErr } = await supabase
.from("figures")
.select("is_active")
.eq("figure_id", stmt.figure_id)
.single();
if (figErr || !fig || fig.is_active !== true) {
console.warn("Figure inactive: embedding deferred", { statement_id, figure_id: stmt.figure_id
});
waitUntil(logPipelineEvent(supabase, statement_id, "DEFERRED", {
reason: "Figure inactive",
}));
return json(409, { error: "Figure is not active; embedding compute deferred" });
}
const dbText = typeof stmt.text === "string" ? stmt.text : "";
if (!dbText) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Statement text missing",
}));
return json(400, { error: "Statement text missing in DB" });
}
if (dbText.length < MIN_TEXT_LENGTH) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Text too short",
length: dbText.length,
}));
return json(400, { error: "Statement text too short for embedding" });
}
if (dbText.length > MAX_TEXT_LENGTH) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Text too long",
length: dbText.length,
}));
return json(400, { error: "Statement text too long for embedding" });
}
// Token-proxy cap (cheap): word count guard
const wordCount = dbText.trim().split(/\s+/).filter(Boolean).length;
if (wordCount > MAX_WORDS_PROXY) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Token estimate exceeded",
word_count: wordCount,
}));
return json(400, { error: "Text exceeds token estimate", word_count: wordCount });
}
// Text drift detection → pipeline_event (queryable)
if (body.text && body.text.trim() !== dbText) {
console.warn("Text drift detected: caller text differs from DB", {
statement_id,
caller_text_length: body.text.length,
db_text_length: dbText.length,
});
// Log as ERROR with specific reason (queryable for monitoring)
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "CALLER_TEXT_DRIFT",
caller_text_length: body.text.length,
db_text_length: dbText.length,
note: "Embedding proceeds with DB text; caller text ignored",
}));
// Don't block - proceed with DB text
}
// ------------------------------------------------------------------------
// Advisory lock: prevent concurrent double-charge on same statement
// A1 V7.71 RPC: acquire_embedding_lock(p_statement_id) - NO timeout param
// ------------------------------------------------------------------------
const { data: lockAcquired, error: lockErr } = await supabase.rpc(
"acquire_embedding_lock",
{ p_statement_id: statement_id }
);
if (lockErr) {
console.error("Embedding lock RPC failed", { statement_id, error: lockErr.message });
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Lock acquisition failed",
error: lockErr.message,
}));
return json(500, { error: "Lock acquisition failed (see logs)" });
}
if (!lockAcquired) {
waitUntil(logPipelineEvent(supabase, statement_id, "DEFERRED", {
reason: "Lock not acquired - concurrent processing",
}));
return json(409, {
error: "Another worker is already processing this embedding",
retry_after_seconds: 5,
});
}
const releaseLock = async () => {
const { error } = await supabase.rpc("release_embedding_lock", {
p_statement_id: statement_id,
});
if (error) {
console.error("Failed to release embedding lock", { statement_id, error: error.message });
}
};
try {
// ----------------------------------------------------------------------
// Re-check statement under lock (revocation/embedding race mitigation)
// ----------------------------------------------------------------------
const { data: lockedStmt, error: lockedErr } = await supabase
.from("statements")
.select("embedding, is_revoked")
.eq("statement_id", statement_id)
.single();
if (lockedErr || !lockedStmt) {
console.error("Locked re-fetch failed", { statement_id, error: lockedErr?.message });
throw new Error("Locked re-fetch failed");
}
if (lockedStmt.embedding !== null) {
waitUntil(logPipelineEvent(supabase, statement_id, "DEFERRED", {
reason: "Embedding set by concurrent process",
}));
return json(200, {
statement_id,
already_embedded: true,
model_used: modelUsed,
elapsed_ms: Date.now() - startedAt,
});
}
if (lockedStmt.is_revoked === true) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
reason: "Statement revoked after lock",
}));
return json(409, { error: "Statement is revoked" });
}
// ----------------------------------------------------------------------
// 2) Call OpenAI embeddings API (with retries)
// ----------------------------------------------------------------------
const { data: openaiData, attempts: totalAttempts } = await
fetchOpenAIEmbedding(modelUsed, dbText);
const embedding: number[] = openaiData.data[0].embedding;
// ----------------------------------------------------------------------
// 3) Persist embedding (RPC enforces write-once; computes baseline_delta)
// ----------------------------------------------------------------------
const { error: embedError } = await supabase.rpc("set_statement_embedding", {
p_statement_id: statement_id,
p_embedding: embedding,
});
if (embedError) {
console.error("Embedding write failed", { statement_id, error: embedError.message });
throw new Error("Embedding write failed (see logs for details)");
}
// ----------------------------------------------------------------------
// 4) Re-fetch baseline_delta (and confirm embedding exists)
// ----------------------------------------------------------------------
const { data: post, error: postErr } = await supabase
.from("statements")
.select("embedding, baseline_delta")
.eq("statement_id", statement_id)
.single();
if (postErr) {
console.error("Post-fetch failed", { statement_id, error: postErr.message });
throw new Error("Post-fetch failed (see logs)");
}
const baselineDelta = post?.baseline_delta ?? null;
// ----------------------------------------------------------------------
// 5) Cost logging (best-effort + non-blocking, but noisy on failure)
// ----------------------------------------------------------------------
const tokenCount =
openaiData?.usage?.total_tokens ??
openaiData?.usage?.prompt_tokens ??
0;
const tokenCountMissing = !openaiData?.usage?.total_tokens &&
!openaiData?.usage?.prompt_tokens;
const estimatedCost =
OPENAI_EMBED_COST_PER_1M_TOKENS !== null
? (tokenCount / 1_000_000) * OPENAI_EMBED_COST_PER_1M_TOKENS
: 0;
waitUntil(
supabase
.from("cost_log")
.insert({
statement_id,
operation: "EMBEDDING",
provider: "OPENAI",
model: modelUsed,
endpoint: "embeddings",
token_count: tokenCount,
estimated_cost_usd: estimatedCost,
})
.then(({ error }: { error: any }) => {
if (error) {
console.error("CRITICAL: cost_log insert failed", {
statement_id,
model: modelUsed,
token_count: tokenCount,
error: error.message,
});
}
})
);
// ----------------------------------------------------------------------
// 6) Log SUCCESS (include token_count_missing for monitoring)
// ----------------------------------------------------------------------
waitUntil(logPipelineEvent(supabase, statement_id, "SUCCESS", {
embedding_length: embedding.length,
baseline_delta: baselineDelta,
token_count: tokenCount,
token_count_missing: tokenCountMissing,
total_attempts: totalAttempts,
elapsed_ms: Date.now() - startedAt,
}));
return json(200, {
success: true,
statement_id,
embedding_length: embedding.length,
baseline_delta: baselineDelta,
baseline_delta_deferred: baselineDelta === null,
baseline_delta_reason:
baselineDelta === null
? "Insufficient prior statements (<30) for baseline window"
: "Computed",
model_used: modelUsed,
total_attempts: totalAttempts,
elapsed_ms: Date.now() - startedAt,
});
} finally {
await releaseLock();
}
} catch (error: any) {
console.error("generate-embedding error", {
statement_id,
message: error?.message,
name: error?.name,
stack: error?.stack,
});
// Log ERROR to pipeline_events
if (supabase && statement_id) {
waitUntil(logPipelineEvent(supabase, statement_id, "ERROR", {
message: error?.message,
name: error?.name,
}));
}
// Sanitized outward error
return json(500, { error: "Embedding failed (see logs)" });
}
});
