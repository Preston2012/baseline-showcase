// ========================================================================
// SUPABASE EDGE FUNCTION: get-statement (A9C v1.0.2 - FINAL)
// Path: supabase/functions/get-statement/index.ts
//
// Fetch a single statement with its analyses and consensus.
// Public read endpoint (anon key). No auth required.
// Revoked statements return 404. Inactive figures return 404.
//
// FIXES APPLIED (V1.0.0 → V1.0.1):
// B1: Explicit column lists instead of select("*") - prevents leaking internals
// B2: Cache-Control removed (POST responses not cacheable per HTTP spec)
// H1: Added figures.is_active filter via view or explicit check
// H3: Env validation inside handler with JSON error responses
// H4: is_revoked defense-in-depth added (later removed in V1.0.2 - view is the guard)
// M1: Consolidated CORS into single withCors helper
//
// FIXES APPLIED (V1.0.1 → V1.0.2 - RECONCILED FROM GPT + GROK AUDITS):
// H4: Removed dead is_revoked check (column not in SELECT; view is the guard)
//
// CROSS-ARTIFACT DEPENDENCIES:
// A1: v_statements_public, v_statement_analysis, v_statement_consensus views
// (must exist - confirm against A1 schema)
// A7A: analyses rows
// A7B: consensus rows
//
// FLAGS FOR A1 CONFIRMATION:
// - v_statements_public: must exist, must filter is_revoked = false
// - v_statement_analysis: must exist, must not expose raw_response
// - v_statement_consensus: must exist
// - All views must be accessible via anon key (RLS / grant)
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── ENV (read at module level, validated per-request) ────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_ANON_KEY = String(Deno.env.get("SUPABASE_ANON_KEY") || "").trim();
// ── Public-safe column lists─────────────────────────────────────────────────
// V1.0.1 FIX (B1): Never select("*") on public endpoints.
// These must match the view definitions in A1. If a view already restricts
// columns, this is defense-in-depth. If views expose too much, this is the guard.
const STATEMENT_COLUMNS = [
"statement_id",
"figure_id",
"figure_name",
"statement_text",
"context_before",
"context_after",
"source_url",
"stated_at",
"ingestion_time",
"baseline_delta",
"topics",
].join(", ");
const ANALYSIS_COLUMNS = [
"analysis_id",
"statement_id",
"model_provider",
"model_version",
"prompt_version",
"repetition",
"novelty",
"affective_language_rate",
"topic_entropy",
"framing",
"analyzed_at",
].join(", ");
const CONSENSUS_COLUMNS = [
"consensus_id",
"statement_id",
"repetition_avg",
"repetition_stddev",
"novelty_avg",
"novelty_stddev",
"affective_language_rate_avg",
"affective_language_rate_stddev",
"topic_entropy_avg",
"topic_entropy_stddev",
"baseline_delta_avg",
"framing_consensus",
"framing_agreement_count",
"framing_split",
"variance_detected",
"signal_rank",
"signal_components",
"model_versions",
"models_included",
"model_count",
"computed_at",
].join(", ");
// ── Helpers──────────────────────────────────────────────────────────────────
// V1.0.1 FIX (M1): Single CORS helper used everywhere. No separate jsonResponse CORS.
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
// V1.0.1 FIX (B2): No Cache-Control - POST responses are not cacheable per HTTP spec
return new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json" },
});
}
function isUuid(id: string): boolean {
return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);
}
// ── Main Handler─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
if (req.method === "OPTIONS") return withCors(new Response("ok", { status: 200 }));
if (req.method !== "POST") return withCors(jsonResponse({ error: "Method not allowed" },
405));

const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
if (killswitchActive) {
  return withCors(jsonResponse({ error: "Service temporarily unavailable", reason: "maintenance" }, 503));
}

try {
// V1.0.1 FIX (H3): Env validation inside handler
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
return withCors(jsonResponse({ error: "Missing SUPABASE_URL or SUPABASE_ANON_KEY" }, 500));
}
const body = await req.json().catch(() => ({}));
const statement_id = body?.statement_id;
if (!statement_id || typeof statement_id !== "string" || !isUuid(statement_id)) {
return withCors(jsonResponse({ error: "statement_id must be a valid UUID" }, 400));
}
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
// ── Fetch statement──────────────────────────────────────────────────
// V1.0.1 FIX (B1): Explicit columns
const { data: statement, error: stmtErr } = await supabase
.from("v_statements_public")
.select(STATEMENT_COLUMNS)
.eq("statement_id", statement_id)
.maybeSingle();
if (stmtErr) throw new Error(`Statement fetch failed: ${stmtErr.message}`);
if (!statement) return withCors(jsonResponse({ error: "Statement not found" }, 404));
// Note: is_revoked + is_active filtering handled by v_statements_public view (A9A V1.0.1).
// No defense-in-depth check needed - column not selected, view is the guard.
// ── Fetch analyses───────────────────────────────────────────────────
// V1.0.1 FIX (B1): Explicit columns - no raw_response, no internal fields
const { data: analyses, error: analysesErr } = await supabase
.from("v_statement_analysis")
.select(ANALYSIS_COLUMNS)
.eq("statement_id", statement_id)
.order("model_provider", { ascending: true });
if (analysesErr) throw new Error(`Analyses fetch failed: ${analysesErr.message}`);
// ── Fetch consensus (may not exist) ──────────────────────────────────
const { data: consensus, error: consensusErr } = await supabase
.from("v_statement_consensus")
.select(CONSENSUS_COLUMNS)
.eq("statement_id", statement_id)
.maybeSingle();
if (consensusErr) throw new Error(`Consensus fetch failed: ${consensusErr.message}`);
return withCors(
jsonResponse({
statement,
analyses: analyses || [],
consensus: consensus || null,
}),
);
} catch (error: any) {
console.error("[get-statement] error", error);
return withCors(jsonResponse({ error: "Internal error" }, 500));
}
});

