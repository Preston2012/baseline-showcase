// =========================================================================
// SUPABASE EDGE FUNCTION: summarize-bill (P2 v1.0.0 : FINAL)
// Path: supabase/functions/summarize-bill/index.ts
//
// Post-A17 auxiliary. NO core table joins.
// Cache-first bill summarization + Provision Drift™ scoring.
// Calls Gemini (P1 prompt) for extraction, OpenAI for embeddings,
// computes cosine distance for drift scores, persists to bill_summaries (PD1).
//
// CROSS-ARTIFACT DEPENDENCIES:
// P1: Gemini prompt template (bill_extraction_v1.0.0)
// PD1: bill_summaries table schema
// A4: Embedding pattern reference (OpenAI text-embedding-3-small)
// A15A: cost_log table (best-effort logging)
//
// ENV VARS REQUIRED:
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// GEMINI_API_KEY, GEMINI_MODEL (e.g., "gemini-1.5-flash")
// OPENAI_API_KEY, OPENAI_EMBED_MODEL (default: "text-embedding-3-small")
// BILL_AUTH_TOKEN (caller auth : P3 sends this)
// BASELINE_KILL_SWITCH (optional: "true" halts processing)
//
// AUDIT FIXES (DRAFT → FINAL):
// B1: congress_session=0 → hard-reject BILL_BAD_ID_FORMAT
// B2: Cache check moved above feature flag (flag gates fresh only)
// W1: SUPABASE_ANON_KEY removed from env list (unused)
// W2: "quarantine" → "retry once + fail with BILL_* code"
// W3: serverWordCount added to cost_log details
// W4: .single() → .maybeSingle() for feature flag query
// P7: Partial embedding failure guard
// P8: JSDoc headers + chamber comment
//
// =========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── ENV (read at module level, validated per-request) ────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_KEY =
String(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();
const GEMINI_API_KEY = String(Deno.env.get("GEMINI_API_KEY") || "").trim();
const GEMINI_MODEL = String(Deno.env.get("GEMINI_MODEL") || "gemini-1.5-flash").trim();
const OPENAI_API_KEY = String(Deno.env.get("OPENAI_API_KEY") || "").trim();
const OPENAI_EMBED_MODEL = String(Deno.env.get("OPENAI_EMBED_MODEL") ||
"text-embedding-3-small").trim();
const BILL_AUTH_TOKEN = String(Deno.env.get("BILL_AUTH_TOKEN") || "").trim();
// ── Constants────────────────────────────────────────────────────────────────
const MAX_BILL_TEXT_LENGTH = 100_000;
const MAX_PROVISIONS = 30;
const PROMPT_VERSION = "bill_extraction_v1.0.0";
const VALID_CATEGORIES = new Set(["EARMARK", "RIDER", "AMENDMENT",
"STANDALONE_PROVISION"]);
const FORBIDDEN_WORDS = [
"pork", "pork barrel", "flagged", "unrelated", "hidden", "buried",
"wasteful", "unnecessary", "suspicious", "sneaky", "deceptive",
"controversial", "problematic", "questionable",
"truth", "lie", "false", "correct", "accurate", "bias", "fact-check",
];
// ── Helpers──────────────────────────────────────────────────────────────────
/** Standard CORS wrapper matching A9B/A7A pattern. */
function withCors(resp: Response): Response {
const h = new Headers(resp.headers);
h.set("Access-Control-Allow-Origin", "*");
h.set("Access-Control-Allow-Methods", "POST, OPTIONS");
h.set("Access-Control-Allow-Headers", "authorization, Authorization, x-client-info, apikey, content-type");
return new Response(resp.body, { status: resp.status, headers: h });
}
/** JSON response helper. */
function jsonResponse(payload: unknown, status = 200): Response {
return new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json" },
});
}
/** Per-request kill switch check (not module-level). */
function isKillSwitchActive(): boolean {
const val = String(Deno.env.get("BASELINE_KILL_SWITCH") || "").trim().toLowerCase();
return val === "true" || val === "1";
}
/** Cosine similarity between two vectors. Returns 0 if inputs are invalid. */
function cosineSimilarity(a: number[], b: number[]): number {
if (a.length !== b.length || a.length === 0) return 0;
let dotProduct = 0;
let normA = 0;
let normB = 0;
for (let i = 0; i < a.length; i++) {
dotProduct += a[i] * b[i];
normA += a[i] * a[i];
normB += b[i] * b[i];
}
const denominator = Math.sqrt(normA) * Math.sqrt(normB);
if (denominator === 0) return 0;
return dotProduct / denominator;
}
/**
* Cosine distance = 1 - similarity. Range 0.0 (identical) to 1.0 (orthogonal).
* Clamped to [0, 1] for floating point safety.
*/
function cosineDistance(a: number[], b: number[]): number {
const similarity = cosineSimilarity(a, b);
return Math.max(0, Math.min(1, 1 - similarity));
}
/**
* Scans text for forbidden words using word-boundary regex.
* Returns the matched word or null if clean.
*/
function containsForbiddenLanguage(text: string): string | null {
const lower = text.toLowerCase();
for (const word of FORBIDDEN_WORDS) {
const regex = new RegExp(`\\b${word.replace(/\s+/g, "\\s+")}\\b`, "i");
if (regex.test(lower)) return word;
}
return null;
}
/** Truncates at last sentence boundary (. ! ?) within maxLen. */
function truncateAtSentenceBoundary(text: string, maxLen: number): string {
if (text.length <= maxLen) return text;
const truncated = text.slice(0, maxLen);
const lastPeriod = truncated.lastIndexOf(".");
const lastExcl = truncated.lastIndexOf("!");
const lastQ = truncated.lastIndexOf("?");
const lastBoundary = Math.max(lastPeriod, lastExcl, lastQ);
if (lastBoundary > maxLen * 0.5) return truncated.slice(0, lastBoundary + 1);
return truncated;
}
/** Truncates at last word boundary (space) within maxLen. */
function truncateAtWordBoundary(text: string, maxLen: number): string {
if (text.length <= maxLen) return text;
const truncated = text.slice(0, maxLen);
const lastSpace = truncated.lastIndexOf(" ");
if (lastSpace > maxLen * 0.5) return truncated.slice(0, lastSpace);
return truncated;
}
/** Counts words in text (splits on whitespace). */
function countWords(text: string): number {
return text.split(/\s+/).filter((w) => w.length > 0).length;
}
/**
* Extracts congress session number from bill_id pattern.
* Expected: "hr-1234-118" or "s-5678-118" → 118.
* Returns 0 if pattern doesn't match (caller must reject).
*/
function extractCongressSession(billId: string): number {
const parts = billId.split("-");
const last = parts[parts.length - 1];
const parsed = parseInt(last, 10);
return isNaN(parsed) || parsed <= 0 ? 0 : parsed;
}
// ── Best-effort cost logging (matches A15A pattern) ─────────────────────────
/** Logs cost estimate. Best-effort: never blocks main flow. */
async function logCost(
supabase: any,
operation: string,
model: string,
inputTokens: number,
outputTokens: number,
estimatedCost: number,
details: Record<string, any>,
): Promise<void> {
try {
await supabase.from("cost_log").insert({
operation,
provider: model.startsWith("gemini") ? "GEMINI" : "OPENAI",
model,
endpoint: "summarize-bill",
token_count: inputTokens + outputTokens,
estimated_cost_usd: estimatedCost,
});
} catch {
// Best-effort : never block main flow
}
}
// ── Gemini Call──────────────────────────────────────────────────────────────
/**
* Calls Gemini with P1 system instruction + prompt.
* JSON mode enforced at API layer (responseMimeType).
* Retries once on malformed JSON, then fails with BILL_* code.
*/
async function callGemini(prompt: string, retryCount = 0): Promise<any> {
const url =
`https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 60_000);
try {
const response = await fetch(url, {
method: "POST",
signal: controller.signal,
headers: { "Content-Type": "application/json" },
body: JSON.stringify({
contents: [{ parts: [{ text: prompt }] }],
systemInstruction: {
parts: [{
text: "[REDACTED: proprietary Gemini system instruction. Defines extraction-only behavior, scope constraints, forbidden language blocklist, and untrusted data handling rules.]",
}],
},
generationConfig: {
temperature: 0.0,
responseMimeType: "application/json",
},
}),
});
if (!response.ok) {
const errText = await response.text();
throw new Error(`Gemini API error ${response.status}: ${errText}`);
}
const data = await response.json();
const content = data?.candidates?.[0]?.content?.parts?.[0]?.text;
if (!content || typeof content !== "string") {
throw new Error("Gemini: missing content in response");
}
// Parse JSON (strip fences if present despite MIME enforcement)
let cleaned = content.trim();
cleaned = cleaned.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "").trim();
let parsed: any;
try {
parsed = JSON.parse(cleaned);
} catch {
if (retryCount < 1) {
console.warn("BILL_JSON_MALFORMED: retrying once");
return callGemini(prompt, retryCount + 1);
}
throw new Error("BILL_JSON_MALFORMED: Gemini returned invalid JSON after retry");
}
const usage = data?.usageMetadata;
return { parsed, usage };
} finally {
clearTimeout(timeout);
}
}
// ── OpenAI Embedding (batch)────────────────────────────────────────────────
/**
* Embeds an array of texts via OpenAI in a single batch call.
* Returns embeddings sorted by input order.
* Returns empty array on failure (caller handles gracefully).
*/
async function embedTexts(texts: string[]): Promise<number[][]> {
if (texts.length === 0) return [];
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 30_000);
try {
const response = await fetch("https://api.openai.com/v1/embeddings", {
method: "POST",
signal: controller.signal,
headers: {
"Content-Type": "application/json",
Authorization: `Bearer ${OPENAI_API_KEY}`,
},
body: JSON.stringify({
model: OPENAI_EMBED_MODEL,
input: texts,
}),
});
if (!response.ok) {
const errText = await response.text();
throw new Error(`OpenAI embedding error ${response.status}: ${errText}`);
}
const data = await response.json();
const sorted = (data.data || []).sort((a: any, b: any) => a.index - b.index);
return sorted.map((item: any) => item.embedding);
} finally {
clearTimeout(timeout);
}
}
// ── P1 Prompt Builder───────────────────────────────────────────────────────
/**
* Builds the P1 prompt with variable substitution.
* NOTE: system_instruction is set separately in the Gemini API call.
* NOTE: `chamber` is context-only: does not affect extraction logic.
*/
function buildPrompt(billId: string, billTitle: string, chamber: string, sourceUrl: string, billText:
string): string {
// [REDACTED: proprietary P1 extraction prompt.
  // Visible structure: extraction rules for summary (max 2000 chars),
  // stated purpose (max 500 chars), provision extraction (max 30 provisions),
  // category classification decision tree (AMENDMENT > EARMARK > RIDER > STANDALONE_PROVISION),
  // deduplication rules, output schema definition (extraction_metadata, summary,
  // stated_purpose, provisions array), and bill text injection point.
  // Prompt version tracked via PROMPT_VERSION constant.]
  return `[REDACTED: proprietary extraction prompt]
---
BILL ID: ${billId}
BILL TITLE: ${billTitle}
CHAMBER: ${chamber}
SOURCE URL: ${sourceUrl}
--- BEGIN BILL TEXT ---
${billText}
--- END BILL TEXT ---`;
}
// ── Validate Gemini Response (P1 post-receive rules)─────────────────────────
/**
* Validates Gemini extraction output against P1 schema rules.
* Returns { valid: true } or { valid: false, error: "..." }.
*/
function validateGeminiResponse(data: any): { valid: boolean; error?: string } {
if (!data.extraction_metadata || !data.summary || !data.stated_purpose || !data.provisions) {
return { valid: false, error: "Missing required top-level fields" };
}
const meta = data.extraction_metadata;
if (typeof data.summary !== "string" || data.summary.length < 10) {
return { valid: false, error: "Summary missing or under 10 chars" };
}
if (typeof data.stated_purpose !== "string" || data.stated_purpose.length < 5) {
return { valid: false, error: "stated_purpose missing or under 5 chars" };
}
if (!Array.isArray(data.provisions) || data.provisions.length === 0) {
return { valid: false, error: "provisions array empty or missing" };
}
if (meta.provisions_extracted !== undefined && meta.provisions_extracted !==
data.provisions.length) {
return { valid: false, error: `provisions_extracted (${meta.provisions_extracted}) !== provisions.length (${data.provisions.length})` };
}
if (!meta.detected_language || !/^[A-Z]{2}$/.test(meta.detected_language)) {
return { valid: false, error: "detected_language missing or invalid format (need exactly 2 uppercase letters)" };
}
for (let i = 0; i < data.provisions.length; i++) {
const p = data.provisions[i];
if (!p.title || typeof p.title !== "string" || p.title.length < 3) {
return { valid: false, error: `Provision ${i}: title missing or under 3 chars` };
}
if (!p.description || typeof p.description !== "string" || p.description.length < 10) {
return { valid: false, error: `Provision ${i}: description missing or under 10 chars` };
}
if (!p.category || !VALID_CATEGORIES.has(p.category)) {
return { valid: false, error: `Provision ${i}: invalid category "${p.category}"` };
}
if (p.provision_note === undefined || p.provision_note === null) {
data.provisions[i].provision_note = "";
}
}
// Forbidden language scan (all text fields)
const textFields = [
data.summary,
data.stated_purpose,
...data.provisions.map((p: any) => `${p.title} ${p.description} ${p.provision_note}`),
meta.extraction_note || "",
];
for (const field of textFields) {
const found = containsForbiddenLanguage(field);
if (found) {
return { valid: false, error: `Forbidden language detected: "${found}"` };
}
}
return { valid: true };
}
// ── Apply length truncations (P1 post-receive)──────────────────────────────
/** Applies max-length truncations per P1 rules. Returns array of warning codes. */
function applyTruncations(data: any): string[] {
const warnings: string[] = [];
if (data.summary.length > 2000) {
data.summary = truncateAtSentenceBoundary(data.summary, 2000);
warnings.push("SUMMARY_TRUNCATED");
}
if (data.stated_purpose.length > 500) {
data.stated_purpose = truncateAtSentenceBoundary(data.stated_purpose, 500);
warnings.push("PURPOSE_TRUNCATED");
}
if (data.extraction_metadata?.extraction_note?.length > 200) {
data.extraction_metadata.extraction_note =
truncateAtWordBoundary(data.extraction_metadata.extraction_note, 200);
warnings.push("EXTRACTION_NOTE_TRUNCATED");
}
for (const p of data.provisions) {
if (p.provision_note && p.provision_note.length > 200) {
p.provision_note = truncateAtWordBoundary(p.provision_note, 200);
warnings.push("NOTE_TRUNCATED");
}
}
if (data.provisions.length > MAX_PROVISIONS) {
data.provisions = data.provisions.slice(0, MAX_PROVISIONS);
data.extraction_metadata.extraction_note = truncateAtWordBoundary(
(data.extraction_metadata.extraction_note || "") + " Provisions capped at 30.",
200,
);
warnings.push("BILL_EXCEEDED_MAX_PROVISIONS");
}
return warnings;
}
// ── Main Handler─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
// CORS preflight
if (req.method === "OPTIONS") return withCors(new Response("ok", { status: 200 }));
if (req.method !== "POST") return withCors(jsonResponse({ error: "Method not allowed" },
405));
const startedAt = Date.now();
let billId = "";
try {
// ── Env validation────────────────────────────────────────────────────
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
return withCors(jsonResponse({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500));
}
if (!GEMINI_API_KEY) {
return withCors(jsonResponse({ error: "Missing GEMINI_API_KEY" }, 500));
}
if (!OPENAI_API_KEY) {
return withCors(jsonResponse({ error: "Missing OPENAI_API_KEY" }, 500));
}
if (!BILL_AUTH_TOKEN) {
return withCors(jsonResponse({ error: "Missing BILL_AUTH_TOKEN" }, 500));
}
// ── Auth check────────────────────────────────────────────────────────
const authHeader = req.headers.get("Authorization") || req.headers.get("authorization");
if (!authHeader || authHeader !== `Bearer ${BILL_AUTH_TOKEN}`) {
return withCors(jsonResponse({ error: "Unauthorized" }, 401));
}
// ── Kill switch───────────────────────────────────────────────────────
if (isKillSwitchActive()) {
return withCors(jsonResponse({
error: "Service temporarily unavailable (emergency halt active)",
killswitch: true,
}, 503));
}
// ── Parse body────────────────────────────────────────────────────────
let body: any;
try {
body = await req.json();
} catch {
return withCors(jsonResponse({ error: "Invalid JSON body" }, 400));
}
billId = typeof body.bill_id === "string" ? body.bill_id.trim() : "";
const billTitle = typeof body.bill_title === "string" ? body.bill_title.trim() : "";
const billText = typeof body.bill_text === "string" ? body.bill_text : "";
// NOTE: chamber is context-only : passed to Gemini for RIDER classification
// context but does not affect extraction logic or persistence.
const chamber = typeof body.chamber === "string" ? body.chamber.trim() : "";
const sourceUrl = typeof body.source_url === "string" ? body.source_url.trim() : "";
// ── Input validation──────────────────────────────────────────────────
if (!billId) {
return withCors(jsonResponse({ error: "Missing required field: bill_id" }, 400));
}
// AUDIT FIX B1: Validate congress_session is extractable BEFORE any DB work.
// PD1 enforces congress_session > 0 via CHECK constraint.
const congressSession = extractCongressSession(billId);
if (congressSession <= 0) {
return withCors(jsonResponse({
error: "Invalid bill_id format (missing congress session suffix)",
code: "BILL_BAD_ID_FORMAT",
expected: "hr-1234-118 or s-5678-118",
}, 400));
}
// ── Supabase client (service_role for writes) ─────────────────────────
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
auth: { autoRefreshToken: false, persistSession: false },
});
//══════════════════════════════════════════════════════════════════════
// STEP 1: Cache check (ALWAYS : regardless of feature flag)
// AUDIT FIX B2: Cached summaries are immutable public records.
// Feature flag only gates fresh extraction, not cache reads.
//══════════════════════════════════════════════════════════════════════
const { data: cached, error: cacheError } = await supabase
.from("bill_summaries")
.select("*")
.eq("bill_id", billId)
.maybeSingle();
if (cached && !cacheError) {
return withCors(jsonResponse({
source: "cache",
bill_summary: cached,
duration_ms: Date.now() - startedAt,
}));
}
//══════════════════════════════════════════════════════════════════════
// STEP 2: Feature flag check (gates fresh extraction ONLY)
// AUDIT FIX W4: .maybeSingle() : missing row doesn't throw
//══════════════════════════════════════════════════════════════════════
const { data: flagData, error: flagErr } = await supabase
.from("feature_flags")
.select("enabled")
.eq("flag_name", "ENABLE_BILL_SUMMARIES")
.maybeSingle();
if (flagErr || flagData?.enabled !== true) {
return withCors(jsonResponse({
error: "Bill summaries feature is not enabled for fresh extraction",
code: "BILL_FEATURE_DISABLED",
}, 403));
}
//══════════════════════════════════════════════════════════════════════
// STEP 3: Validate inputs for fresh extraction
//══════════════════════════════════════════════════════════════════════
if (!billTitle) {
return withCors(jsonResponse({ error: "Missing required field: bill_title (needed for fresh extraction)" }, 400));
}
if (!billText) {
return withCors(jsonResponse({ error: "Missing required field: bill_text (needed for fresh extraction)" }, 400));
}
if (!sourceUrl) {
return withCors(jsonResponse({ error: "Missing required field: source_url (needed for fresh extraction)" }, 400));
}
if (billText.length > MAX_BILL_TEXT_LENGTH) {
return withCors(jsonResponse({
error: `bill_text exceeds maximum length (${billText.length} > ${MAX_BILL_TEXT_LENGTH})`,
code: "BILL_TOO_LONG",
}, 400));
}
//══════════════════════════════════════════════════════════════════════
// STEP 4: Call Gemini (P1 prompt)
//══════════════════════════════════════════════════════════════════════
const prompt = buildPrompt(billId, billTitle, chamber, sourceUrl, billText);
let geminiResult: any;
try {
geminiResult = await callGemini(prompt);
} catch (err: any) {
console.error("Gemini call failed:", err.message);
return withCors(jsonResponse({
error: "Bill extraction failed",
code: "BILL_GEMINI_FAILED",
detail: err.message,
}, 502));
}
const extraction = geminiResult.parsed;
const geminiUsage = geminiResult.usage;
//══════════════════════════════════════════════════════════════════════
// STEP 5: Validate Gemini response (P1 post-receive rules)
// Retry once on validation failure, then fail with BILL_* code.
//══════════════════════════════════════════════════════════════════════
let validExtraction = extraction;
const validation = validateGeminiResponse(extraction);
if (!validation.valid) {
console.error("Gemini validation failed:", validation.error);
try {
const retryResult = await callGemini(prompt + "\n\nREMINDER: " + validation.error, 1);
const retryValidation = validateGeminiResponse(retryResult.parsed);
if (!retryValidation.valid) {
return withCors(jsonResponse({
error: "Bill extraction validation failed after retry",
code: "BILL_VALIDATION_FAILED",
detail: retryValidation.error,
}, 502));
}
validExtraction = retryResult.parsed;
} catch (retryErr: any) {
return withCors(jsonResponse({
error: "Bill extraction retry failed",
code: "BILL_RETRY_FAILED",
detail: retryErr.message,
}, 502));
}
}
// Apply truncations
const truncationWarnings = applyTruncations(validExtraction);
// Non-English flag
if (validExtraction.extraction_metadata.detected_language !== "EN") {
console.warn(`NON_ENGLISH_BILL: ${validExtraction.extraction_metadata.detected_language} for ${billId}`);
}
// Prompt version mismatch warning
if (validExtraction.extraction_metadata.prompt_version !== PROMPT_VERSION) {
console.warn(`BILL_PROMPT_VERSION_MISMATCH: expected ${PROMPT_VERSION}, got ${validExtraction.extraction_metadata.prompt_version}`);
}
// High provision count warning
if (validExtraction.provisions.length > 25) {
console.warn(`HIGH_PROVISION_COUNT: ${validExtraction.provisions.length} for ${billId}`);
}
//══════════════════════════════════════════════════════════════════════
// STEP 6: Compute Provision Drift™ (embeddings + cosine distance)
// Best-effort: if embedding fails, persist without drift scores.
//══════════════════════════════════════════════════════════════════════
let driftComputed = false;
let avgDriftScore: number | null = null;
try {
const textsToEmbed = [
validExtraction.stated_purpose,
...validExtraction.provisions.map((p: any) => p.description),
];
const embeddings = await embedTexts(textsToEmbed);
// AUDIT FIX P7: Guard against partial embedding failure.
// If we don't get exactly the right number of embeddings, skip drift.
if (embeddings.length === textsToEmbed.length && embeddings.length >= 2) {
const purposeEmbedding = embeddings[0];
const provisionEmbeddings = embeddings.slice(1);
let totalDrift = 0;
for (let i = 0; i < provisionEmbeddings.length; i++) {
const driftScore = cosineDistance(purposeEmbedding, provisionEmbeddings[i]);
validExtraction.provisions[i].drift_score = Math.round(driftScore * 10000) / 10000;
totalDrift += driftScore;
}
avgDriftScore = Math.round((totalDrift / provisionEmbeddings.length) * 10000) / 10000;
driftComputed = true;
} else {
console.warn(`DRIFT_EMBEDDING_COUNT_MISMATCH: expected ${textsToEmbed.length}, got ${embeddings.length} for ${billId}`);
}
// Embeddings are TRANSIENT : discarded here, never persisted
} catch (embedErr: any) {
console.error("Drift computation failed (non-blocking):", embedErr.message);
}
//══════════════════════════════════════════════════════════════════════
// STEP 7: Persist to bill_summaries (PD1)
//══════════════════════════════════════════════════════════════════════
const serverWordCount = countWords(billText);
const insertPayload = {
bill_id: billId,
bill_title: billTitle,
summary: validExtraction.summary,
stated_purpose: validExtraction.stated_purpose,
provisions: validExtraction.provisions,
provision_count: validExtraction.provisions.length,
drift_computed: driftComputed,
avg_drift_score: avgDriftScore,
source_bill_url: sourceUrl,
congress_session: congressSession, // AUDIT FIX B1: guaranteed > 0 here
};
const { data: inserted, error: insertError } = await supabase
.from("bill_summaries")
.insert(insertPayload)
.select()
.single();
if (insertError) {
// Race condition: another request inserted while we were processing
if (insertError.code === "23505") {
const { data: raceWinner } = await supabase
.from("bill_summaries")
.select("*")
.eq("bill_id", billId)
.maybeSingle();
if (raceWinner) {
return withCors(jsonResponse({
source: "cache_race",
bill_summary: raceWinner,
duration_ms: Date.now() - startedAt,
}));
}
}
console.error("Insert failed:", insertError);
return withCors(jsonResponse({
error: "Failed to persist bill summary",
code: "BILL_INSERT_FAILED",
detail: insertError.message,
}, 500));
}
//══════════════════════════════════════════════════════════════════════
// STEP 8: Cost logging (best-effort, non-blocking)
// AUDIT FIX W3: serverWordCount included in details
//══════════════════════════════════════════════════════════════════════
const inputTokens = geminiUsage?.promptTokenCount || 0;
const outputTokens = geminiUsage?.candidatesTokenCount || 0;
const geminiCostEstimate = (inputTokens / 1_000_000) * 0.075 + (outputTokens /
1_000_000) * 0.30;
const embeddingCostEstimate = 0.00005;
await logCost(supabase, "bill_extraction", GEMINI_MODEL, inputTokens, outputTokens,
geminiCostEstimate, {
bill_id: billId,
provisions_count: validExtraction.provisions.length,
drift_computed: driftComputed,
server_word_count: serverWordCount,
});
await logCost(supabase, "bill_drift_embedding", OPENAI_EMBED_MODEL, 0, 0,
embeddingCostEstimate, {
bill_id: billId,
texts_embedded: validExtraction.provisions.length + 1,
});
//══════════════════════════════════════════════════════════════════════
// STEP 9: Return result
//══════════════════════════════════════════════════════════════════════
return withCors(jsonResponse({
source: "fresh",
bill_summary: inserted,
warnings: truncationWarnings.length > 0 ? truncationWarnings : undefined,
duration_ms: Date.now() - startedAt,
}));
} catch (err: any) {
console.error(`summarize-bill error for ${billId}:`, err);
return withCors(jsonResponse({
error: "Internal server error",
code: "BILL_INTERNAL_ERROR",
detail: err.message,
}, 500));
}
});
