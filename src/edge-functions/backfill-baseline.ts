// ========================================================================
// SUPABASE EDGE FUNCTION: backfill-baseline (A12B v1.0.2 — FINAL)
// Path: supabase/functions/backfill-baseline/index.ts
//
// Admin-only endpoint to trigger baseline_delta backfill for a figure.
// Calls A12A's backfill_baseline_delta RPC. Service-role only.
//
// FIXES APPLIED (V1.0.0 → V1.0.1):
// B1: logEvent rewritten — direct PostgREST insert using A11A V1.0.2 schema
// B2: Added BASELINE_KILL_SWITCH check
// B3: Env ! assertions → validated inside handler
// B4: Stage 'EMBED' → 'EMBEDDING' (matches A11A enum)
// H1: Dry run no longer exposes statement text
// H2: Retry only on transient errors (not constraint violations)
// H3: Error catch reuses supabase instance
// M1: Added OPTIONS handler for robustness
//
// FIXES APPLIED (V1.0.1 → V1.0.2 — RECONCILED FROM GPT + GROK AUDITS):
// 1: Kill switch moved from module scope to per-request (matches A7B/A9B)
//
// CROSS-ARTIFACT DEPENDENCIES:
// A11A: pipeline_events table (stage, event_type, details)
// A12A: backfill_baseline_delta RPC
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── ENV (read at module level, validated per-request) ────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_KEY =
String(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();
const BACKFILL_AUTH_TOKEN = String(Deno.env.get("BACKFILL_AUTH_TOKEN") ||
"").trim();
// ── Helpers──────────────────────────────────────────────────────────────────
function jsonResponse(payload: unknown, status = 200): Response {
return new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json" },
});
}
function isUuid(id: string): boolean {
return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);
}
// V1.0.1 FIX (B1/B4): Direct PostgREST insert using A11A V1.0.2 schema
// Stage = EMBEDDING (matches A11A enum). event_type + details, no level/message.
async function logPipelineEvent(
supabase: any,
figureId: string | null,
eventType: string,
details: Record<string, any>,
): Promise<void> {
try {
await supabase.from("pipeline_events").insert({
statement_id: null,
stage: "EMBEDDING",
event_type: eventType,
details: { operation: "BACKFILL_BASELINE_DELTA", figure_id: figureId, ...details },
});
} catch {
// Best-effort — never block main flow
}
}
// V1.0.1 FIX (H2): Only retry on transient errors
function isTransientError(err: any): boolean {
const msg = String(err?.message || "").toLowerCase();
return (
msg.includes("timeout") ||
msg.includes("network") ||
msg.includes("fetch") ||
msg.includes("econnrefused") ||
msg.includes("503") ||
msg.includes("429")
);
}
async function retry<T>(fn: () => Promise<T>, maxTry = 3): Promise<T> {
let lastErr: any = null;
for (let i = 0; i < maxTry; i++) {
try {
return await fn();
} catch (e) {
lastErr = e;
if (!isTransientError(e) || i === maxTry - 1) throw e;
const delayMs = 2000 * Math.pow(2, i);
await new Promise((r) => setTimeout(r, delayMs));
}
}
throw lastErr;
}
// ── Main Handler─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
// V1.0.1 FIX (M1): OPTIONS handler for robustness
if (req.method === "OPTIONS") return new Response("ok", { status: 200 });
if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
// V1.0.2 FIX (1): Kill switch evaluated per-request (not module scope)
const killSwitchRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
const killSwitchActive = killSwitchRaw === "TRUE" || killSwitchRaw.toLowerCase() === "true";
if (killSwitchActive) {
console.log("[backfill-baseline] BASELINE_KILL_SWITCH active — rejecting request");
return jsonResponse(
{ error: "Service halted", reason: "BASELINE_KILL_SWITCH active" },
503,
);
}
let supabase: any = null;
let figureIdForLog: string | null = null;
try {
// V1.0.1 FIX (B3): Env validation inside handler
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
return jsonResponse({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);
}
if (!BACKFILL_AUTH_TOKEN) {
return jsonResponse({ error: "Missing BACKFILL_AUTH_TOKEN" }, 500);
}
// Auth
const authHeader = req.headers.get("Authorization") || req.headers.get("authorization");
if (!authHeader || authHeader !== `Bearer ${BACKFILL_AUTH_TOKEN}`) {
return jsonResponse({ error: "Unauthorized" }, 401);
}
const body = await req.json().catch(() => ({}));
const figure_id = body?.figure_id;
const limit = Math.min(Math.max(1, Number(body?.limit) || 50), 500);
const dry_run = body?.dry_run === true;
figureIdForLog = typeof figure_id === "string" ? figure_id : null;
if (!figure_id || typeof figure_id !== "string" || !isUuid(figure_id)) {
return jsonResponse({ error: "figure_id must be a valid UUID" }, 400);
}
supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// Verify figure exists + active
const { data: figure, error: figureErr } = await supabase
.from("figures")
.select("figure_id, name, is_active")
.eq("figure_id", figure_id)
.single();
if (figureErr || !figure) return jsonResponse({ error: "Figure not found" }, 404);
if (!figure.is_active) {
return jsonResponse(
{
error: "Figure is not active. Backfill is only allowed for active figures.",
figure_id,
figure_name: figure.name,
},
409,
);
}
// ── Dry run────────────────────────────────────────────────────────────
if (dry_run) {
// V1.0.1 FIX (H1): No statement text exposed — ID + timestamp only
const { data: candidates, error: candidatesErr } = await supabase
.from("statements")
.select("statement_id, ingestion_time")
.eq("figure_id", figure_id)
.is("baseline_delta", null)
.not("embedding", "is", null)
.eq("is_revoked", false)
.order("ingestion_time", { ascending: true })
.limit(limit);
if (candidatesErr) throw new Error(`Dry run query failed: ${candidatesErr.message}`);
await logPipelineEvent(supabase, figure_id, "INFO", {
dry_run: true,
limit,
would_process: (candidates || []).length,
});
return jsonResponse({
dry_run: true,
figure_id,
figure_name: figure.name,
would_process: (candidates || []).length,
limit,
candidates: (candidates || []).map((s: any) => ({
statement_id: s.statement_id,
ingestion_time: s.ingestion_time,
})),
});
}
// ── Execute backfill───────────────────────────────────────────────────
await logPipelineEvent(supabase, figure_id, "START", { limit });
const result = await retry(async () => {
const { data, error } = await supabase.rpc("backfill_baseline_delta", {
p_figure_id: figure_id,
p_limit: limit,
});
if (error) throw new Error(error.message);
return data as any;
});
await logPipelineEvent(supabase, figure_id, "SUCCESS", {
limit,
updated_count: result?.updated_count ?? 0,
skipped_count: result?.skipped_count ?? 0,
});
return jsonResponse({
success: true,
figure_id,
figure_name: figure.name,
updated_count: result.updated_count,
skipped_count: result.skipped_count,
message: result.message,
next_steps:
result.updated_count > 0
? "Run Analysis + Consensus workflow to process backfilled statements"
: null,
});
} catch (error: any) {
console.error("[backfill-baseline] error", error);
// V1.0.1 FIX (H3): Reuse supabase instance from try block
if (supabase) {
await logPipelineEvent(supabase, figureIdForLog, "ERROR", {
error: String(error?.message || "Backfill failed").slice(0, 500),
});
}
return jsonResponse({ error: "Internal error" }, 500);
}
});
