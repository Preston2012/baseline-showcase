// Baseline Edge Function: compute-consensus (1 of 22)
// Reconciles independent AI analyses into consensus scores
// Core scoring algorithm redacted
// Full implementation: Droiddna2013@gmail.com
// github.com/Preston2012/baseline-showcase

// ========================================================================
// SUPABASE EDGE FUNCTION: compute-consensus (A7B v1.0.2 — FINAL)
// Deploy to: supabase/functions/compute-consensus/index.ts
//
// FIXES APPLIED (V1.0.0 → V1.0.1):
// B1: KILLSWITCH → BASELINE_KILL_SWITCH (matches A4/A5B/A5C/A5D/A6/A7A)
// B2: pipeline_events schema aligned with A4 (statement_id, stage, event_type, details)
// H1: Env validation moved inside handler (top-level throw kills entire function)
// H2: Kill switch moved to per-request (not module-load), matches A7A V1.3.3
// H3: analyses SELECT uses specific columns (not SELECT *)
// M1: Added startup log on first request
//
// FIXES APPLIED (V1.0.1 → V1.0.2 — RECONCILED FROM GPT + GROK AUDITS):
// 1: Validate analysis rows before inclusion (metrics + framing present + valid)
// 5: VARIANCE_THRESHOLD NaN guard (fallback to default if malformed env)
// 6: prompt_version consistency check across analyses rows
// 7: models_included added to START log
//
// CROSS-ARTIFACT DEPENDENCIES:
// A1: consensus table, analyses table, pipeline_events table
// A3: Framing labels (5 values)
// A4: pipeline_events schema (statement_id, stage, event_type, details)
// A7A: Produces analyses rows consumed here
//
// FLAGS FOR A1 CONFIRMATION:
// - consensus.framing_split: JSONB? (we write {label: count} map or null)
// - consensus.signal_components: JSONB? (we write {repetition, novelty, baseline_delta})
// - consensus.model_versions: JSONB? (we write {openai: "...", anthropic: "..."})
// - consensus.models_included: TEXT[]? (we write sorted provider name array)
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── ENV (read at module level, validated per-request) ────────────────────────
// V1.0.1 FIX (H1): No top-level throws — validation inside handler with JSON errors
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_KEY =
String(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();
const CONSENSUS_AUTH_TOKEN = String(Deno.env.get("CONSENSUS_AUTH_TOKEN") ||
"").trim();
// Configurable thresholds
// V1.0.2 FIX (5): NaN guard — fallback to default if env is malformed
const _varianceRaw = Number(String(Deno.env.get("VARIANCE_THRESHOLD") ||
"15.0").trim());
const VARIANCE_THRESHOLD = Number.isFinite(_varianceRaw) ? _varianceRaw : 20.0;
// Provider set (schema currently supports 2–3)
const ALLOWED_PROVIDERS = new Set(["OPENAI", "ANTHROPIC", "XAI"]);
// Framing labels must match A1 enum + A3/A7A
const VALID_FRAMING = new Set([
"Adversarial / Oppositional",
"Problem Identification",
"Commitment / Forward-Looking",
"Justification / Reactive",
"Imperative / Directive",
]);
// ── Helpers──────────────────────────────────────────────────────────────────
function withCors(resp: Response): Response {
const h = new Headers(resp.headers);
h.set("Access-Control-Allow-Origin", "*");
h.set("Access-Control-Allow-Methods", "POST, OPTIONS");
h.set(
"Access-Control-Allow-Headers",
"authorization, Authorization, x-client-info, apikey, content-type",
);
return new Response(resp.body, { status: resp.status, headers: h });
}
function jsonResponse(payload: unknown, status = 200): Response {
return new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json" },
});
}
function isUuid(id: string): boolean {
return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
id,
);
}
// V1.0.1 FIX (B2): Pipeline events using A4-aligned schema
// (statement_id, stage, event_type, details) — NOT (event_type, severity, message, context)
async function logPipelineEvent(
supabase: any,
statementId: string | null,
eventType: string,
details: Record<string, any>,
): Promise<void> {
try {
await supabase.from("pipeline_events").insert({
statement_id: statementId,
stage: "CONSENSUS",
event_type: eventType,
details,
});
} catch {
// Best-effort — never block main flow
}
}
// ── Main Handler─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
if (req.method === "OPTIONS") return withCors(new Response("ok", { status: 200 }));
if (req.method !== "POST") {
return withCors(jsonResponse({ error: "Method not allowed" }, 405));
}
// V1.0.1 FIX (H2): Kill switch per-request (not module-load)
const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
// V1.0.1 FIX (M1): Startup log
console.log("[compute-consensus] request received", {
BASELINE_KILL_SWITCH: ksRaw || "(not set)",
VARIANCE_THRESHOLD,
});
if (killswitchActive) {
console.log("[compute-consensus] BASELINE_KILL_SWITCH active — rejecting request");
return withCors(
jsonResponse({ error: "Service halted", reason: "BASELINE_KILL_SWITCH active" }, 503),
);
}
let supabase: any = null;
let statement_id: string | null = null;
try {
// V1.0.1 FIX (H1): Env validation inside handler with JSON error responses
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
return withCors(jsonResponse({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500));
}
if (!CONSENSUS_AUTH_TOKEN) {
return withCors(jsonResponse({ error: "Missing CONSENSUS_AUTH_TOKEN" }, 500));
}
// Auth (robust casing) — accept CONSENSUS_AUTH_TOKEN or service_role JWT
const authHeader =
req.headers.get("Authorization") || req.headers.get("authorization");
const token = (authHeader || "").replace("Bearer ", "");
let authed = false;
if (token === CONSENSUS_AUTH_TOKEN) { authed = true; }
else {
  try {
    const parts = token.split(".");
    if (parts.length === 3) {
      const payload = JSON.parse(atob(parts[1]));
      if (payload.role === "service_role") { authed = true; }
    }
  } catch { /* not a JWT */ }
}
if (!authed) {
return withCors(jsonResponse({ error: "Unauthorized" }, 401));
}
const body = await req.json().catch(() => ({}));
statement_id = body?.statement_id;
if (!statement_id || typeof statement_id !== "string" || !isUuid(statement_id)) {
return withCors(jsonResponse({ error: "statement_id must be a valid UUID" }, 400));
}
supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// Log start event
// V1.0.2 FIX (7): Include allowed providers for ops visibility
await logPipelineEvent(supabase, statement_id, "START", {
workflow: "A7B",
variance_threshold: VARIANCE_THRESHOLD,
allowed_providers: Array.from(ALLOWED_PROVIDERS).sort(),
});
// Idempotency: write-once consensus
const { data: existing, error: existingErr } = await supabase
.from("consensus")
.select("consensus_id")
.eq("statement_id", statement_id)
.maybeSingle();
if (existingErr) {
console.error("[compute-consensus] consensus lookup failed:", existingErr.message);
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
if (existing) {
return withCors(jsonResponse({ already_exists: true, statement_id }, 200));
}
// Fetch statement
const { data: statement, error: stmtErr } = await supabase
.from("statements")
.select("statement_id, baseline_delta, is_revoked")
.eq("statement_id", statement_id)
.single();
if (stmtErr || !statement) {
return withCors(jsonResponse({ error: "Statement not found" }, 404));
}
if (statement.is_revoked) {
return withCors(jsonResponse({ error: "Statement is revoked" }, 410));
}
// baseline_delta: use neutral default (50.0) when NULL (first ~30 statements
// per figure lack enough prior data to compute a real delta).
// Previously this deferred the entire consensus — now we proceed with a
// neutral midpoint so calibration statements still get scored.
const baselineDeltaRaw = statement.baseline_delta;
const baselineDeltaIsNull = baselineDeltaRaw === null || baselineDeltaRaw === undefined;
let baselineDelta: number;
if (baselineDeltaIsNull) {
baselineDelta = 50.0; // neutral midpoint — "deviation unknown"
console.log("[compute-consensus] baseline_delta NULL, using neutral default 50.0", { statement_id });
} else {
baselineDelta = Number(baselineDeltaRaw);
if (Number.isNaN(baselineDelta) || baselineDelta < 0 || baselineDelta > 100) {
console.error("[compute-consensus] invalid baseline_delta:", baselineDeltaRaw);
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
}
// V1.0.1 FIX (H3): Select only needed columns (not SELECT *)
const { data: analysesRaw, error: analysisErr } = await supabase
.from("analyses")
.select("model_provider, model_version, prompt_version, repetition, novelty, affective_language_rate, topic_entropy, framing")
.eq("statement_id", statement_id);
if (analysisErr) {
console.error("[compute-consensus] analyses fetch failed:", analysisErr.message);
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
// Deterministic provider selection + cap (max 3)
// V1.0.2 FIX (1): Validate each row has usable metrics + valid framing before inclusion.
// Prevents "2 analyses available" but only 1 has actual usable data.
const METRIC_FIELDS = ["repetition", "novelty", "affective_language_rate", "topic_entropy"];
const analyses = (analysesRaw || [])
.filter((a: any) => ALLOWED_PROVIDERS.has(String(a?.model_provider || "")))
.filter((a: any) => {
const metricsOk = METRIC_FIELDS.every((k) => Number.isFinite(Number(a?.[k])));
const framingOk = VALID_FRAMING.has(String(a?.framing || ""));
return metricsOk && framingOk;
})
.sort((a: any, b: any) =>
String(a?.model_provider || "").localeCompare(String(b?.model_provider || "")),
)
.slice(0, 3);
if (analyses.length < 2) {
await logPipelineEvent(supabase, statement_id, "NOT_READY", {
workflow: "A7B",
analyses_found: analyses.length,
});
return withCors(
jsonResponse(
{ error: "Fewer than 2 analyses available. Run analyze-statement first." },
409,
),
);
}
// V1.0.2 FIX (6): Verify all analyses share the same prompt_version.
// Prevents blending results from different prompt generations.
const promptVersions = new Set(analyses.map((a: any) => String(a?.prompt_version || "")));
if (promptVersions.size > 1) {
await logPipelineEvent(supabase, statement_id, "ERROR", {
workflow: "A7B",
reason: "Mixed prompt_versions across analyses",
versions_found: Array.from(promptVersions).sort(),
});
return withCors(
jsonResponse(
{
error: "prompt_version_mismatch",
statement_id,
versions_found: Array.from(promptVersions).sort(),
},
409,
),
);
}
// ============================================================
// AVERAGES + STDDEV
// - Validate 0–100 range before averaging
// - Use sample stddev (N-1) to avoid underestimating with N=2–3
// ============================================================
const metricMap: Record<string, string> = {
repetition: "repetition_avg",
novelty: "novelty_avg",
affective_language_rate: "affective_language_rate_avg",
topic_entropy: "topic_entropy_avg",
};
const stddevMap: Record<string, string> = {
repetition: "repetition_stddev",
novelty: "novelty_stddev",
affective_language_rate: "affective_language_rate_stddev",
topic_entropy: "topic_entropy_stddev",
};
const consensusRow: Record<string, any> = { statement_id };
for (const [sourceField, targetAvgField] of Object.entries(metricMap)) {
const values = analyses
.map((a: any) => Number(a?.[sourceField]))
.filter((v) => !Number.isNaN(v));
if (values.length === 0) {
throw new Error(`NaN guard: no valid values for metric '${sourceField}'`);
}
const invalid = values.filter((v) => v < 0 || v > 100);
if (invalid.length > 0) {
throw new Error(
`Invalid range for ${sourceField}: values must be 0-100, found ${invalid.join(", ")}`,
);
}
const avg = values.reduce((sum, v) => sum + v, 0) / values.length;
if (Number.isNaN(avg)) throw new Error(`NaN in ${sourceField} avg`);
const denom = values.length > 1 ? values.length - 1 : 1; // sample variance
const variance = values.reduce((sum, v) => sum + Math.pow(v - avg, 2), 0) / denom;
const stddev = Math.sqrt(variance);
consensusRow[targetAvgField] = Math.round(avg * 100) / 100;
consensusRow[stddevMap[sourceField]] = Math.round(stddev * 100) / 100;
}
consensusRow.baseline_delta_avg = Math.round(baselineDelta * 100) / 100;
// ============================================================
// FRAMING MAJORITY VOTE
// - Validate framing labels to satisfy A1 constraints
// - Deterministic tie-break (alphabetic)
// - framing_split uses framing-label keys (A1 constraint-compatible)
// ============================================================
const framingCounts: Record<string, number> = {};
for (const a of analyses) {
const framing = String(a?.framing || "");
if (!framing) continue;
framingCounts[framing] = (framingCounts[framing] || 0) + 1;
}
if (Object.keys(framingCounts).length === 0) {
throw new Error("No valid framing values found across analyses");
}
const invalidFramingKeys = Object.keys(framingCounts).filter((k) =>
!VALID_FRAMING.has(k));
if (invalidFramingKeys.length > 0) {
throw new Error(`Invalid framing labels in analyses: ${invalidFramingKeys.join(", ")}`);
}
const maxCount = Math.max(...Object.values(framingCounts));
const majority = Object.keys(framingCounts)
.sort()
.find((k) => framingCounts[k] === maxCount)!;
consensusRow.framing_consensus = majority;
consensusRow.framing_agreement_count = maxCount;
consensusRow.framing_split = maxCount < analyses.length ? framingCounts : null;
// ============================================================
// VARIANCE DETECTION
// ============================================================
const maxStddev = Math.max(
Number(consensusRow.repetition_stddev) || 0,
Number(consensusRow.novelty_stddev) || 0,
Number(consensusRow.affective_language_rate_stddev) || 0,
Number(consensusRow.topic_entropy_stddev) || 0,
);
consensusRow.variance_detected =
maxStddev > VARIANCE_THRESHOLD && maxCount < analyses.length;
// ============================================================
// SIGNAL RANK
// Signal Rank Formula (v1.0):
// - baseline_delta: 40% (how different from historical baseline)
// - novelty: 35% (new semantic content)
// - inverted repetition: 25% (100 - repetition; rewards fresh phrasing)
// Range: 0-100, higher = more signal value
// TODO: make weights configurable via env for tuning/A-B tests.
// ============================================================
consensusRow.signal_components = {
repetition: consensusRow.repetition_avg,
novelty: consensusRow.novelty_avg,
baseline_delta: consensusRow.baseline_delta_avg,
baseline_delta_defaulted: baselineDeltaIsNull,
};
consensusRow.model_versions = {};
for (const a of analyses) {
const key = String(a.model_provider || "").toLowerCase();
consensusRow.model_versions[key] = a.model_version;
}
consensusRow.models_included = analyses.map((a: any) =>
String(a.model_provider)).sort();
consensusRow.model_count = analyses.length;
const bd = Number(consensusRow.baseline_delta_avg) || 0;
const nov = Number(consensusRow.novelty_avg) || 0;
const rep = Number(consensusRow.repetition_avg) || 0;
consensusRow.signal_rank =
Math.round((bd * 0.4 + nov * 0.35 + (100 - rep) * 0.25) * 100) / 100;
// ============================================================
// RE-CHECK REVOKED (race guard) BEFORE INSERT
// ============================================================
const { data: stmtRecheck, error: reErr } = await supabase
.from("statements")
.select("is_revoked")
.eq("statement_id", statement_id)
.single();
if (reErr) {
console.error("[compute-consensus] revoke recheck failed:", reErr.message);
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
if (stmtRecheck?.is_revoked) {
return withCors(
jsonResponse({ error: "Statement was revoked during consensus computation" }, 410),
);
}
// ============================================================
// WRITE (handle unique-race gracefully)
// ============================================================
const { error: writeErr } = await supabase.from("consensus").insert(consensusRow);
if (writeErr) {
// 23505 unique_violation -> another caller won the race; treat as success
if ((writeErr as any).code === "23505") {
return withCors(jsonResponse({ already_exists: true, statement_id, race_resolved: true },
200));
}
console.error("[compute-consensus] write failed:", (writeErr as any)?.message || writeErr);
await logPipelineEvent(supabase, statement_id, "ERROR", {
workflow: "A7B",
error: String((writeErr as any)?.message || "write failed").slice(0, 500),
});
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
// Log success
await logPipelineEvent(supabase, statement_id, "SUCCESS", {
workflow: "A7B",
signal_rank: consensusRow.signal_rank,
variance_detected: consensusRow.variance_detected,
models_included: consensusRow.models_included,
});
return withCors(
jsonResponse(
{
success: true,
statement_id,
signal_rank: consensusRow.signal_rank,
variance_detected: consensusRow.variance_detected,
framing_consensus: consensusRow.framing_consensus,
models_analyzed: analyses.length,
},
200,
),
);
} catch (error: any) {
console.error("[compute-consensus] fatal", error);
// Log error event (best-effort)
if (supabase && statement_id) {
await logPipelineEvent(supabase, statement_id, "ERROR", {
workflow: "A7B",
error: String(error?.message || "Internal error").slice(0, 500),
});
}
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
});
