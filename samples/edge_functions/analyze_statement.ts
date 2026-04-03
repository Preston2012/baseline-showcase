// Baseline Edge Function: analyze-statement (1 of 22)
// Multi-provider AI analysis pipeline
// Prompt templates and provider API details redacted
// Full implementation: Droiddna2013@gmail.com
// github.com/Preston2012/baseline-showcase

// ========================================================================
// SUPABASE EDGE FUNCTION: analyze-statement (A7A v1.3.3 — FINAL)
// Deploy to: supabase/functions/analyze-statement/index.ts
//
// FIXES APPLIED (V1.3.1 → V1.3.2):
// B1: Added BASELINE_KILL_SWITCH check (matches A4/A5B/A5C/A5D/A6)
// B2: Removed metadata column from cost_log inserts (column doesn't exist)
// H1: Removed dead safeTrim/reject duplication — kept safeTrim as defense-in-depth
// H2: MAX_STATEMENT_CHARS aligned to 2500 (A5A enforces 2000; margin for safety)
// M1: Added pipeline_events logging (START/SUCCESS/ERROR) via A4-aligned schema
//
// FIXES APPLIED (V1.3.2 → V1.3.3 — RECONCILED FROM GPT + GROK AUDITS):
// B1: Removed raw_sql RPC from logPipelineEvent (security footgun; direct insert only)
// B2: Hardened JSON parsing — strip non-JSON prefix/suffix for Anthropic/xAI
// B3: Added Access-Control-Allow-Methods to CORS helper
// M1: Kill switch moved to per-request (not module-load) for runtime toggle support
//
// CROSS-ARTIFACT DEPENDENCIES:
// A1: insert_analyses_pair RPC, analyses table, analyses_audit table, pipeline_events
// A3: Prompt version analysis_v1.3.1, framing labels (5 values)
// A4: pipeline_events schema (statement_id, stage, event_type, details)
// A5A: Statement text 2000 chars, context 1000 chars
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── Environment──────────────────────────────────────────────────────────────
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") || "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
// XAI is OPTIONAL. If ENABLE_XAI=true but config missing, we degrade gracefully.
const ENABLE_XAI = (Deno.env.get("ENABLE_XAI") || "").toLowerCase() === "true";
const XAI_API_KEY = Deno.env.get("XAI_API_KEY") || "";
const XAI_MODEL = (Deno.env.get("XAI_ANALYZE_MODEL") || "").trim();
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const ANALYZE_AUTH_TOKEN = Deno.env.get("ANALYZE_AUTH_TOKEN") || "";
// V1.3.3 FIX (M1): Kill switch computed per-request inside handler (not module-load)
// This allows runtime toggle without redeploy on platforms that persist Edge Function instances.
// Required provider models (env-driven; no hardcode)
const OPENAI_MODEL = (Deno.env.get("OPENAI_ANALYZE_MODEL") || "").trim();
const ANTHROPIC_MODEL = (Deno.env.get("ANTHROPIC_ANALYZE_MODEL") || "").trim();
// Optional pricing map (env-driven; no fake hardcodes)
const ANALYSIS_PRICING_JSON = (Deno.env.get("ANALYSIS_PRICING_JSON") || "").trim();
// ── Constants────────────────────────────────────────────────────────────────
const PROMPT_VERSION = "analysis_v1.3.1";
const PER_CALL_TIMEOUT_MS = 20000;
// V1.3.2 FIX (H2): Aligned with A5A's 2000 char limit + safety margin
const MAX_STATEMENT_CHARS = 2500;
const MAX_CONTEXT_CHARS = 1000;
const SYSTEM_PROMPT =
  // [REDACTED] - Neutral linguistic analysis prompt template.
  // Instructs models to output strict JSON metrics:
  // repetition, novelty, affective_language_rate, topic_entropy, framing.
  // No editorializing. See private repo for full prompt.
  "";
const VALID_FRAMING = [
"Adversarial / Oppositional",
"Problem Identification",
"Commitment / Forward-Looking",
"Justification / Reactive",
"Imperative / Directive",
];
// ── Types────────────────────────────────────────────────────────────────────
interface ProviderResult {
result: Record<string, any>;
rawResponse: Record<string, any>;
modelVersion: string;
durationMs: number;
}
type PricingMap = Record<string, { input_per_1m: number; output_per_1m: number }>;
// ── Helpers──────────────────────────────────────────────────────────────────
function jsonResponse(payload: unknown, status = 200): Response {
return new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
});
}
function withCors(resp: Response): Response {
const h = new Headers(resp.headers);
h.set("Access-Control-Allow-Origin", "*");
// V1.3.3 FIX (B3): Added Allow-Methods (browsers may block preflight without it)
h.set("Access-Control-Allow-Methods", "POST, OPTIONS");
h.set(
"Access-Control-Allow-Headers",
"authorization, Authorization, x-client-info, apikey, content-type",
);
return new Response(resp.body, { status: resp.status, headers: h });
}
function isUuid(id: string): boolean {
return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
id,
);
}
function parseStrictJsonOrThrow(text: string, provider: string, allowFenceStripping: boolean) {
let cleaned = (text || "").trim();
if (allowFenceStripping) {
cleaned = cleaned
.replace(/^```(?:json)?\s*\n?/i, "")
.replace(/\n?```\s*$/i, "")
.trim();
}
// V1.3.3 FIX (B2): Strip non-JSON prefix/suffix for providers without
// enforced JSON mode (Anthropic, xAI). Handles "Sure, here's the JSON: {...}"
const firstBrace = cleaned.indexOf("{");
const lastBrace = cleaned.lastIndexOf("}");
if (firstBrace > 0 && lastBrace > firstBrace) {
cleaned = cleaned.slice(firstBrace, lastBrace + 1);
}
let parsed: any;
try {
parsed = JSON.parse(cleaned);
} catch {
throw new Error(`${provider}: response was not valid JSON`);
}
return parsed;
}
function validateAnalysisResult(result: any, provider: string): void {
const required = ["repetition", "novelty", "affective_language_rate", "topic_entropy", "framing"];
for (const field of required) {
if (result?.[field] === undefined || result?.[field] === null) {
throw new Error(`${provider}: missing field '${field}'`);
}
}
for (const field of ["repetition", "novelty", "affective_language_rate", "topic_entropy"]) {
const val = Number(result[field]);
if (Number.isNaN(val) || val < 0 || val > 100) {
throw new Error(`${provider}: '${field}' must be 0–100, got ${result[field]}`);
}
// Reject floats rather than rounding silently
if (!Number.isInteger(val)) {
throw new Error(`${provider}: '${field}' must be integer 0–100, got ${result[field]}`);
}
result[field] = val;
}
if (!VALID_FRAMING.includes(String(result.framing))) {
throw new Error(`${provider}: invalid framing label '${result.framing}'`);
}
}
// V1.3.2 FIX (H1): safeTrim used as defense-in-depth only (no separate rejection path)
function safeTrim(s: string, max: number): string {
const t = (s || "").trim();
if (t.length <= max) return t;
return t.slice(0, max);
}
function parsePricingMap(): PricingMap | null {
if (!ANALYSIS_PRICING_JSON) return null;
try {
const parsed = JSON.parse(ANALYSIS_PRICING_JSON);
if (!parsed || typeof parsed !== "object") return null;
return parsed as PricingMap;
} catch {
return null;
}
}
function estimateCost(pricing: PricingMap, model: string, inputTokens: number, outputTokens:
number): number | null {
const rates = pricing[model];
if (!rates) return null;
return (inputTokens / 1_000_000) * rates.input_per_1m + (outputTokens / 1_000_000) *
rates.output_per_1m;
}
// ── Pipeline Events Helper───────────────────────────────────────────────────
// V1.3.3 FIX (B1): Direct insert only — removed raw_sql RPC (security footgun)
// Best-effort: never blocks main flow
async function logPipelineEvent(
supabase: any,
statementId: string | null,
eventType: string,
details: Record<string, any>,
): Promise<void> {
try {
await supabase.from("pipeline_events").insert({
statement_id: statementId,
stage: "ANALYSIS",
event_type: eventType,
details,
});
} catch {
// Best-effort — never block main flow
}
}
// ── Prompt───────────────────────────────────────────────────────────────────
function buildUserPrompt(
figureName: string,
statementText: string,
contextPre: string,
contextPost: string,
baselineEmbeddedCount: number,
): string {
return `Analyze the following statement by ${figureName}.
STATEMENT:
"""
${statementText}
"""
CONTEXT BEFORE:
"""
${contextPre || "N/A"}
"""
CONTEXT AFTER:
"""
${contextPost || "N/A"}
"""
BASELINE CONTEXT:
This figure has made ${baselineEmbeddedCount} prior embedded statements in the system.
Provide a neutral linguistic analysis using these exact metrics:
1. REPETITION (0-100): How much does this statement repeat phrasing, slogans, or structural
patterns commonly associated with this figure's public speech? 0 = completely novel phrasing,
100 = verbatim or near-verbatim repetition of well-known prior language.
2. NOVELTY (0-100): How much new semantic content or distinct claims does this statement
introduce? 0 = no new information relative to the figure's known positions, 100 = entirely new
topic or claim.
3. AFFECTIVE_LANGUAGE_RATE (0-100): What proportion of the statement uses emotionally
charged, evaluative, or intensifying language? 0 = clinical/neutral tone, 100 = highly charged
throughout.
4. TOPIC_ENTROPY (0-100): How semantically coherent vs. scattered is this statement? 0 =
single tight topic, 100 = multiple unrelated topics or fragmented.
5. FRAMING (enum, select exactly one):
- "Adversarial / Oppositional"
- "Problem Identification"
- "Commitment / Forward-Looking"
- "Justification / Reactive"
- "Imperative / Directive"
Output JSON with this exact schema:
{
"repetition": <integer 0-100>,
"novelty": <integer 0-100>,
"affective_language_rate": <integer 0-100>,
"topic_entropy": <integer 0-100>,
"framing": "<one of the five labels above, exactly as written>"
}
Do not include explanations, reasoning, or any other fields.`;
}
// ── Provider: OpenAI─────────────────────────────────────────────────────────
async function callOpenAI(prompt: string): Promise<ProviderResult> {
  // [REDACTED] - OpenAI GPT-4 API integration
  // - Chat completion with JSON mode
  // - Timeout handling, JSON response parsing, duration tracking
  // - Returns ProviderResult with metrics and model version
  // See private repo for full implementation.
  throw new Error("Redacted");
}

// ── Provider: Anthropic──────────────────────────────────────────────────────
async function callAnthropic(prompt: string): Promise<ProviderResult> {
  // [REDACTED] - Anthropic Claude API integration
  // - Messages API with system prompt separation
  // - Timeout handling, JSON response parsing, duration tracking
  // - Returns ProviderResult with metrics and model version
  // See private repo for full implementation.
  throw new Error("Redacted");
}

// ── Provider: xAI (OPTIONAL, NON-FATAL)───────────────────────────────────────
async function callXai(prompt: string): Promise<ProviderResult> {
  // [REDACTED] - xAI Grok API integration
  // - OpenAI-compatible endpoint with Grok model
  // - Timeout handling, JSON response parsing, duration tracking
  // - Returns ProviderResult with metrics and model version
  // See private repo for full implementation.
  throw new Error("Redacted");
}

// ── Main Handler─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
if (req.method === "OPTIONS") return withCors(new Response("ok"));
if (req.method !== "POST") return withCors(jsonResponse({ error: "Method not allowed" },
405));
// V1.3.3 FIX (M1): Kill switch computed per-request (not module-load)
const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
if (killswitchActive) {
console.log("[analyze-statement] BASELINE_KILL_SWITCH active — rejecting request");
return withCors(
jsonResponse(
{ error: "Service halted", reason: "BASELINE_KILL_SWITCH active" },
503,
),
);
}
let supabase: any = null;
let statement_id: string | null = null;
try {
// Required env checks (fail fast)
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
return withCors(jsonResponse({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500));
}
if (!ANALYZE_AUTH_TOKEN) {
return withCors(jsonResponse({ error: "Missing ANALYZE_AUTH_TOKEN" }, 500));
}
if (!OPENAI_API_KEY || !ANTHROPIC_API_KEY) {
return withCors(jsonResponse({ error: "Missing OPENAI_API_KEY or ANTHROPIC_API_KEY" }, 500));
}
if (!OPENAI_MODEL || !ANTHROPIC_MODEL) {
return withCors(jsonResponse({ error: "OPENAI_ANALYZE_MODEL and ANTHROPIC_ANALYZE_MODEL are required" }, 500));
}
// Auth
const authHeader = req.headers.get("Authorization") || req.headers.get("authorization");
if (!authHeader || authHeader !== `Bearer ${ANALYZE_AUTH_TOKEN}`) {
return withCors(jsonResponse({ error: "Unauthorized" }, 401));
}
const body = await req.json().catch(() => ({}));
statement_id = body?.statement_id;
if (!statement_id || typeof statement_id !== "string" || !isUuid(statement_id)) {
return withCors(jsonResponse({ error: "statement_id must be a valid UUID" }, 400));
}
supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// Log start event
await logPipelineEvent(supabase, statement_id, "START", {
workflow: "A7A",
openai_model: OPENAI_MODEL,
anthropic_model: ANTHROPIC_MODEL,
xai_enabled: ENABLE_XAI,
xai_model: XAI_MODEL || null,
});
// Existing analyses + prompt_version guard
const { data: existingAnalyses, error: existErr } = await supabase
.from("analyses")
.select("analysis_id, model_provider, prompt_version, model_version, repetition, novelty, affective_language_rate, topic_entropy, framing")
.eq("statement_id", statement_id);
if (existErr) throw new Error("Existing analyses check failed");
const existingProviders = new Set((existingAnalyses || []).map((a: any) =>
String(a.model_provider)));
const existingPromptVersions = new Set((existingAnalyses || []).map((a: any) =>
String(a.prompt_version || "")));
if (existingPromptVersions.size > 0) {
if (existingPromptVersions.size > 1 || !existingPromptVersions.has(PROMPT_VERSION)) {
return withCors(
jsonResponse(
{
error: "prompt_version_mismatch",
statement_id,
expected: PROMPT_VERSION,
found: Array.from(existingPromptVersions).sort(),
permanent: true,
},
409,
),
);
}
}
const hasOAI = existingProviders.has("OPENAI");
const hasANT = existingProviders.has("ANTHROPIC");
// If only one of OAI/ANT exists -> permanent partial pair state
const pairPartialState = (hasOAI || hasANT) && (hasOAI !== hasANT);
if (pairPartialState) {
return withCors(
jsonResponse(
{
error: "partial_pair_state",
statement_id,
providers_present: Array.from(existingProviders).sort(),
permanent: true,
},
409,
),
);
}
// Determine what needs to run
const needOaiAnt = !hasOAI && !hasANT;
const xaiConfigured = ENABLE_XAI && !!XAI_API_KEY && !!XAI_MODEL;
const needXai = xaiConfigured && !existingProviders.has("XAI");
// Early exit if nothing to do
if (!needOaiAnt && !needXai) {
return withCors(
jsonResponse(
{
already_analyzed: true,
statement_id,
providers_present: Array.from(existingProviders).sort(),
xai_status: existingProviders.has("XAI")
? "already_exists"
: (ENABLE_XAI && !xaiConfigured ? "disabled_missing_config" : "disabled"),
},
200,
),
);
}
// Fetch statement (must have embedding)
const { data: statement, error: stmtErr } = await supabase
.from("statements")
.select("statement_id, figure_id, text, context_pre, context_post, embedding, is_revoked")
.eq("statement_id", statement_id)
.single();
if (stmtErr || !statement) return withCors(jsonResponse({ error: "Statement not found" }, 404));
if (statement.is_revoked) return withCors(jsonResponse({ error: "Statement is revoked" },
410));
if (statement.embedding == null) {
return withCors(jsonResponse({ error: "Embedding not yet computed. Run embedding step first.", statement_id }, 409));
}
// V1.3.2 FIX (H1): safeTrim as defense-in-depth only — no separate rejection path
// A5A already enforces text 2000 chars, context 1000 chars at ingestion time.
// safeTrim caps protect against any future bypass without rejecting valid data.
const textSafe = safeTrim(String(statement.text || ""), MAX_STATEMENT_CHARS);
const preSafe = safeTrim(String(statement.context_pre || ""), MAX_CONTEXT_CHARS);
const postSafe = safeTrim(String(statement.context_post || ""), MAX_CONTEXT_CHARS);
// Figure name (non-fatal)
const { data: figure, error: figErr } = await supabase
.from("figures")
.select("name")
.eq("figure_id", statement.figure_id)
.single();
const figureName = figure?.name || "Unknown";
if (figErr) {
console.warn("[analyze-statement] figure lookup failed (non-fatal)");
}
// Baseline count (estimated to avoid scans)
const { count: baselineCount, error: baseErr } = await supabase
.from("statements")
.select("statement_id", { count: "estimated", head: true })
.eq("figure_id", statement.figure_id)
.neq("statement_id", statement_id)
.eq("is_revoked", false)
.not("embedding", "is", null);
if (baseErr) throw new Error("Baseline count query failed");
const userPrompt = buildUserPrompt(
figureName,
textSafe,
preSafe,
postSafe,
Number(baselineCount || 0),
);
// Execute provider calls
const xaiPromise: Promise<ProviderResult | null> = needXai
? callXai(userPrompt).catch((err) => {
console.error("[analyze-statement] XAI call failed (non-fatal):", err?.message || err);
return null;
})
: Promise.resolve(null);
const [openaiResponse, anthropicResponse, xaiResponse] = (await Promise.all([
needOaiAnt ? callOpenAI(userPrompt) : Promise.resolve(null),
needOaiAnt ? callAnthropic(userPrompt) : Promise.resolve(null),
xaiPromise,
])) as [ProviderResult | null, ProviderResult | null, ProviderResult | null];
// Validate required pair if run
if (needOaiAnt) {
if (!openaiResponse) throw new Error("OpenAI call returned no result");
if (!anthropicResponse) throw new Error("Anthropic call returned no result");
validateAnalysisResult(openaiResponse.result, "OPENAI");
validateAnalysisResult(anthropicResponse.result, "ANTHROPIC");
}
// Validate XAI if present (non-fatal)
let xaiValid: ProviderResult | null = null;
if (xaiResponse) {
try {
validateAnalysisResult(xaiResponse.result, "XAI");
xaiValid = xaiResponse;
} catch (err) {
console.error("[analyze-statement] XAI validation failed (non-fatal):", (err as
Error)?.message || err);
}
}
// If we are ONLY backfilling XAI (OAI/ANT already exist), reconstruct from existing rows.
let reconstructedOpenAI: any = null;
let reconstructedAnthropic: any = null;
let reconstructedOpenAIRaw: any = null;
let reconstructedAnthropicRaw: any = null;
let openaiModelVersionForWrite: string | null = null;
let anthropicModelVersionForWrite: string | null = null;
if (!needOaiAnt && needXai) {
const oaiRow = (existingAnalyses || []).find((r: any) => r.model_provider === "OPENAI");
const antRow = (existingAnalyses || []).find((r: any) => r.model_provider ===
"ANTHROPIC");
if (!oaiRow || !antRow) {
// Shouldn't happen due to partial pair guard, but keep safe.
return withCors(jsonResponse({ error: "Missing required OPENAI/ANTHROPIC pair for XAI backfill", statement_id }, 409));
}
reconstructedOpenAI = {
repetition: Math.round(Number(oaiRow.repetition)),
novelty: Math.round(Number(oaiRow.novelty)),
affective_language_rate: Math.round(Number(oaiRow.affective_language_rate)),
topic_entropy: Math.round(Number(oaiRow.topic_entropy)),
framing: String(oaiRow.framing),
};
reconstructedAnthropic = {
repetition: Math.round(Number(antRow.repetition)),
novelty: Math.round(Number(antRow.novelty)),
affective_language_rate: Math.round(Number(antRow.affective_language_rate)),
topic_entropy: Math.round(Number(antRow.topic_entropy)),
framing: String(antRow.framing),
};
openaiModelVersionForWrite = String(oaiRow.model_version);
anthropicModelVersionForWrite = String(antRow.model_version);
// Pull raw payloads (service_role can read analyses_audit)
const { data: oaiAudit } = await supabase
.from("analyses_audit")
.select("raw_response")
.eq("analysis_id", oaiRow.analysis_id)
.single();
const { data: antAudit } = await supabase
.from("analyses_audit")
.select("raw_response")
.eq("analysis_id", antRow.analysis_id)
.single();
reconstructedOpenAIRaw = oaiAudit?.raw_response ?? { note: "raw_missing" };
reconstructedAnthropicRaw = antAudit?.raw_response ?? { note: "raw_missing" };
}
// Single atomic write using A1 RPC
const rpcParams: any = {
p_statement_id: statement_id,
p_prompt_version: PROMPT_VERSION,
p_openai_model_version: needOaiAnt ? openaiResponse!.modelVersion :
openaiModelVersionForWrite,
p_openai_result: needOaiAnt ? openaiResponse!.result : reconstructedOpenAI,
p_openai_raw: needOaiAnt ? openaiResponse!.rawResponse : reconstructedOpenAIRaw,
p_anthropic_model_version: needOaiAnt ? anthropicResponse!.modelVersion :
anthropicModelVersionForWrite,
p_anthropic_result: needOaiAnt ? anthropicResponse!.result : reconstructedAnthropic,
p_anthropic_raw: needOaiAnt ? anthropicResponse!.rawResponse :
reconstructedAnthropicRaw,
p_xai_model_version: xaiValid ? xaiValid.modelVersion : null,
p_xai_result: xaiValid ? xaiValid.result : null,
p_xai_raw: xaiValid ? xaiValid.rawResponse : null,
};
// If xaiValid is null AND we are not running OAI/ANT, bail safely.
if (!needOaiAnt && needXai && !xaiValid) {
await logPipelineEvent(supabase, statement_id, "ERROR", {
workflow: "A7A",
reason: "XAI backfill failed — call returned no valid result",
xai_status: "call_failed",
});
return withCors(
jsonResponse(
{
error: "xai_failed_nonfatal",
statement_id,
providers_present: Array.from(existingProviders).sort(),
xai_status: "call_failed",
},
502,
),
);
}
const { error: writeErr } = await supabase.rpc("insert_analyses_pair", rpcParams);
if (writeErr) throw new Error("Analyses write failed");
// Post-write providers present (DB truth)
const { data: afterAnalyses, error: afterErr } = await supabase
.from("analyses")
.select("model_provider")
.eq("statement_id", statement_id);
if (afterErr) throw new Error("Post-write analyses check failed");
const providersPresent = new Set((afterAnalyses || []).map((r: any) =>
String(r.model_provider)));
const providersPresentSorted = Array.from(providersPresent).sort();
// V1.3.2 FIX (B2): Cost logging — removed metadata column (doesn't exist in cost_log)
const pricing = parsePricingMap();
const costLoggingEnabled = !!pricing;
if (costLoggingEnabled && needOaiAnt && openaiResponse && anthropicResponse) {
try {
const oaiUsage = (openaiResponse.rawResponse as any)?.usage || {};
const oaiIn = oaiUsage.prompt_tokens || 0;
const oaiOut = oaiUsage.completion_tokens || 0;
const oaiCost = estimateCost(pricing!, openaiResponse.modelVersion, oaiIn, oaiOut);
await supabase.from("cost_log").insert({
statement_id,
operation: "ANALYSIS",
provider: "OPENAI",
model: openaiResponse.modelVersion,
endpoint: "chat/completions",
token_count: oaiIn + oaiOut,
estimated_cost_usd: oaiCost ?? 0,
});
const anthUsage = (anthropicResponse.rawResponse as any)?.usage || {};
const anthIn = anthUsage.input_tokens || 0;
const anthOut = anthUsage.output_tokens || 0;
const anthCost = estimateCost(pricing!, anthropicResponse.modelVersion, anthIn,
anthOut);
await supabase.from("cost_log").insert({
statement_id,
operation: "ANALYSIS",
provider: "ANTHROPIC",
model: anthropicResponse.modelVersion,
endpoint: "messages",
token_count: anthIn + anthOut,
estimated_cost_usd: anthCost ?? 0,
});
} catch (err) {
console.error("[analyze-statement] Cost logging failed:", (err as Error)?.message || err);
}
}
if (costLoggingEnabled && xaiValid) {
try {
const xaiUsage = (xaiValid.rawResponse as any)?.usage || {};
const xaiIn = xaiUsage.prompt_tokens || 0;
const xaiOut = xaiUsage.completion_tokens || 0;
const xaiCost = estimateCost(pricing!, xaiValid.modelVersion, xaiIn, xaiOut);
await supabase.from("cost_log").insert({
statement_id,
operation: "ANALYSIS",
provider: "XAI",
model: xaiValid.modelVersion,
endpoint: "chat/completions",
token_count: xaiIn + xaiOut,
estimated_cost_usd: xaiCost ?? 0,
});
} catch (err) {
console.error("[analyze-statement] XAI cost logging failed:", (err as Error)?.message || err);
}
}
// xai_status (simple + truthful)
let xai_status: string;
if (!ENABLE_XAI) xai_status = "disabled";
else if (ENABLE_XAI && !xaiConfigured) xai_status = "disabled_missing_config";
else if (providersPresent.has("XAI")) xai_status = "success";
else xai_status = "failed";
// Log success
await logPipelineEvent(supabase, statement_id, "SUCCESS", {
workflow: "A7A",
providers_present: providersPresentSorted,
xai_status,
openai_duration_ms: openaiResponse?.durationMs ?? null,
anthropic_duration_ms: anthropicResponse?.durationMs ?? null,
xai_duration_ms: xaiValid?.durationMs ?? null,
});
return withCors(
jsonResponse(
{
success: true,
statement_id,
wrote_new_rows: true,
providers_present: providersPresentSorted,
models_completed: providersPresentSorted,
xai_status,
openai_duration_ms: openaiResponse?.durationMs ?? null,
anthropic_duration_ms: anthropicResponse?.durationMs ?? null,
xai_duration_ms: xaiValid?.durationMs ?? null,
cost_logging_enabled: costLoggingEnabled,
},
200,
),
);
} catch (error: any) {
console.error("[analyze-statement] fatal", error);
// Log error event (best-effort)
if (supabase && statement_id) {
await logPipelineEvent(supabase, statement_id, "ERROR", {
workflow: "A7A",
error: String(error?.message || "Internal error").slice(0, 500),
});
}
return withCors(jsonResponse({ error: error?.message || "Internal error" }, 500));
}
});
