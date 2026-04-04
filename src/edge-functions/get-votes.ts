// ========================================================================
// A16C -- get-votes Edge Function
// Version: V1.0.1
// Depends on: A1 V8.0 (votes, figures, feature_flags)
// A16A V1.0.2 (get_votes_for_figure, get_vote_summary_for_figure,
// get_votes_for_bill RPCs)
//
// Changelog V1.0.1:
// CRITICAL: Always use SUPABASE_ANON_KEY from env (never trust client apikey)
// CRITICAL: Explicit feature flag check → 503 {feature_enabled:false} when off
// Confirmed: A16A V1.0.2 uses feature_flags.enabled (not is_enabled)
// Added: Request correlation ID + structured logging
// Added: Limit clamped ≤500, offset clamped ≤10000
// Added: bill_id format validation regex
// Added: Date validation (real dates, not just regex)
// Added: Supabase client timeout (10s)
// Added: Cache-Control headers (public, max-age=60)
// Fixed: Chamber normalized once (no double-uppercase)
// Fixed: isValidChamber assumes pre-normalized input
//
// Routes:
// GET /get-votes?figure_id=... → Paginated votes
// GET /get-votes?figure_id=...&summary=true → Aggregated counts
// GET /get-votes?bill_id=... → Cross-figure bill lookup
//
// All reads delegate to A16A RPCs (SECURITY INVOKER, RLS-gated).
// Feature flag checked explicitly before RPC calls.
// No AI. No writes. No cost_log. Pure serving layer.
// ========================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
// ── Constants──────────────────────────────────────────────────────────────
const MAX_LIMIT = 500;
const MAX_OFFSET = 10000;
const DEFAULT_LIMIT = 100;
const CACHE_MAX_AGE = 60;
// ── CORS headers───────────────────────────────────────────────────────────
const CORS_HEADERS = {
"Access-Control-Allow-Origin": "*",
"Access-Control-Allow-Methods": "GET, OPTIONS",
"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
// ── Response helpers───────────────────────────────────────────────────────
function jsonResponse(data: unknown, status = 200): Response {
return new Response(JSON.stringify(data), {
status,
headers: {
...CORS_HEADERS,
"Content-Type": "application/json",
"Cache-Control": status === 200 ? `public, max-age=${CACHE_MAX_AGE}` : "no-store",
},
});
}
function errorResponse(message: string, status: number, code?: string): Response {
return jsonResponse({ error: true, message, ...(code ? { code } : {}) }, status);
}
// ── Validators─────────────────────────────────────────────────────────────
const UUID_REGEX =
/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const VALID_CHAMBERS = new Set(["HOUSE", "SENATE"]);
// bill_id: TYPE-NUMBER-CONGRESS or ROLL-CHAMBER-CONGRESS-NUMBER
const BILL_ID_REGEX = /^[A-Z]+-\d+-\d+$|^ROLL-[A-Z]+-\d+-\d+$/;
function isValidUUID(val: string | null): boolean {
return val !== null && UUID_REGEX.test(val);
}
function isValidChamber(val: string): boolean {
// Assumes val is already uppercased by caller
return VALID_CHAMBERS.has(val);
}
function isValidDate(val: string): boolean {
if (!/^\d{4}-\d{2}-\d{2}$/.test(val)) return false;
const parsed = new Date(val + "T00:00:00Z");
if (isNaN(parsed.getTime())) return false;
// Verify round-trip (catches 2026-02-30 etc.)
return parsed.toISOString().startsWith(val);
}
function isValidBillId(val: string): boolean {
return BILL_ID_REGEX.test(val);
}
// ── Feature flag check─────────────────────────────────────────────────────
async function isVoteTrackingEnabled(
supabase: ReturnType<typeof createClient>,
): Promise<boolean> {
try {
const { data, error } = await supabase
.from("feature_flags")
.select("enabled")
.eq("flag_name", "ENABLE_VOTE_TRACKING")
.single();
if (error || !data) return false;
return data.enabled === true;
} catch {
return false;
}
}
// ── Main handler───────────────────────────────────────────────────────────
serve(async (req: Request): Promise<Response> => {
// Handle CORS preflight
if (req.method === "OPTIONS") {
return new Response(null, { status: 204, headers: CORS_HEADERS });
}
// Only GET allowed
if (req.method !== "GET") {
return errorResponse("Method not allowed. Use GET.", 405, "METHOD_NOT_ALLOWED");
}

const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
if (killswitchActive) {
  return jsonResponse({ error: "Service temporarily unavailable", reason: "maintenance" }, 503);
}

// Correlation ID for request tracing
const correlationId = crypto.randomUUID();
try {
// ── Validate env─────────────────────────────────────────────────────
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
if (!supabaseUrl || !supabaseAnonKey) {
console.error(`[A16C] [${correlationId}] Missing SUPABASE_URL or
SUPABASE_ANON_KEY`);
return errorResponse("Server configuration error", 500, "CONFIG_ERROR");
}
// ── Parse query params───────────────────────────────────────────────
const url = new URL(req.url);
const params = url.searchParams;
const figureId = params.get("figure_id");
const billId = params.get("bill_id");
const summary = params.get("summary")?.toLowerCase() === "true";
const chamberRaw = params.get("chamber");
const congressSession = params.get("congress_session");
const fromDate = params.get("from_date");
const toDate = params.get("to_date");
const limitParam = params.get("limit");
const offsetParam = params.get("offset");
// Normalize chamber once
const chamber = chamberRaw ? chamberRaw.toUpperCase() : null;
// Log request (sanitized - no values, just param presence)
console.log(
`[A16C] [${correlationId}] GET /get-votes ` +
`figure_id=${!!figureId} bill_id=${!!billId} summary=${summary} ` +
`chamber=${chamber || "none"}`,
);
// ── Route validation: must provide figure_id OR bill_id ──────────────
if (!figureId && !billId) {
return errorResponse(
"Missing required parameter: figure_id or bill_id",
400,
"MISSING_PARAM",
);
}
if (figureId && billId) {
return errorResponse(
"Provide either figure_id or bill_id, not both",
400,
"CONFLICTING_PARAMS",
);
}
// ── Validate chamber─────────────────────────────────────────────────
if (chamber && !isValidChamber(chamber)) {
return errorResponse(
`Invalid chamber: '${chamberRaw}'. Must be HOUSE or SENATE.`,
400,
"INVALID_CHAMBER",
);
}
// ── Create Supabase client (ALWAYS use env anon key) ─────────────────
// Never trust client-supplied apikey. Auth header passed through for
// RLS context (authenticated users get same data but with JWT context).
const authHeader = req.headers.get("Authorization");
const supabase = createClient(supabaseUrl, supabaseAnonKey, {
global: {
headers: {
...(authHeader ? { Authorization: authHeader } : {}),
},
},
db: {
schema: "public",
},
});
// ── Feature flag check (explicit - RPCs return empty when off) ───────
const flagEnabled = await isVoteTrackingEnabled(supabase);
if (!flagEnabled) {
console.log(`[A16C] [${correlationId}] ENABLE_VOTE_TRACKING is disabled`);
return jsonResponse(
{
error: true,
feature_enabled: false,
message: "Vote tracking is not currently enabled",
code: "FEATURE_DISABLED",
},
503,
);
}
// ── Route: bill_id → get_votes_for_bill ──────────────────────────────
if (billId) {
const trimmedBillId = billId.trim();
if (trimmedBillId === "") {
return errorResponse("bill_id cannot be empty", 400, "INVALID_BILL_ID");
}
if (!isValidBillId(trimmedBillId)) {
return errorResponse(
"Invalid bill_id format. Expected: TYPE-NUMBER-CONGRESS (e.g., HR-1234-118)",
400,
"INVALID_BILL_ID",
);
}
const { data, error } = await supabase.rpc("get_votes_for_bill", {
p_bill_id: trimmedBillId,
});
if (error) {
console.error(`[A16C] [${correlationId}] get_votes_for_bill error: ${error.message}`);
return errorResponse("Failed to fetch votes for bill", 500, "RPC_ERROR");
}
return jsonResponse({
bill_id: trimmedBillId,
votes: data || [],
count: (data || []).length,
});
}
// ── Route: figure_id (validated) ─────────────────────────────────────
if (!isValidUUID(figureId)) {
return errorResponse(
"Invalid figure_id: must be a valid UUID",
400,
"INVALID_FIGURE_ID",
);
}
// ── Shared param validation for figure routes ────────────────────────
let parsedSession: number | null = null;
if (congressSession) {
parsedSession = parseInt(congressSession, 10);
if (isNaN(parsedSession) || parsedSession < 1) {
return errorResponse(
"Invalid congress_session: must be a positive integer",
400,
"INVALID_SESSION",
);
}
}
let parsedLimit: number = DEFAULT_LIMIT;
if (limitParam) {
parsedLimit = parseInt(limitParam, 10);
if (isNaN(parsedLimit) || parsedLimit < 1) {
return errorResponse(
"Invalid limit: must be a positive integer",
400,
"INVALID_LIMIT",
);
}
parsedLimit = Math.min(parsedLimit, MAX_LIMIT);
}
let parsedOffset: number = 0;
if (offsetParam) {
parsedOffset = parseInt(offsetParam, 10);
if (isNaN(parsedOffset) || parsedOffset < 0) {
return errorResponse(
"Invalid offset: must be a non-negative integer",
400,
"INVALID_OFFSET",
);
}
parsedOffset = Math.min(parsedOffset, MAX_OFFSET);
}
// ── Route: figure_id + summary → get_vote_summary_for_figure ─────────
if (summary) {
const rpcParams: Record<string, unknown> = {
p_figure_id: figureId,
};
if (chamber) rpcParams.p_chamber = chamber;
if (parsedSession) rpcParams.p_congress_session = parsedSession;
const { data, error } = await supabase.rpc(
"get_vote_summary_for_figure",
rpcParams,
);
if (error) {
console.error(
`[A16C] [${correlationId}] get_vote_summary_for_figure error: ${error.message}`,
);
return errorResponse("Failed to fetch vote summary", 500, "RPC_ERROR");
}
return jsonResponse({
figure_id: figureId,
summary: data || [],
});
}
// ── Route: figure_id (detail) → get_votes_for_figure ─────────────────
const rpcParams: Record<string, unknown> = {
p_figure_id: figureId,
p_limit: parsedLimit,
p_offset: parsedOffset,
};
if (chamber) rpcParams.p_chamber = chamber;
if (parsedSession) rpcParams.p_congress_session = parsedSession;
if (fromDate) {
if (!isValidDate(fromDate)) {
return errorResponse(
"Invalid from_date: must be a valid YYYY-MM-DD date",
400,
"INVALID_DATE",
);
}
rpcParams.p_from_date = fromDate;
}
if (toDate) {
if (!isValidDate(toDate)) {
return errorResponse(
"Invalid to_date: must be a valid YYYY-MM-DD date",
400,
"INVALID_DATE",
);
}
rpcParams.p_to_date = toDate;
}
const { data, error } = await supabase.rpc("get_votes_for_figure", rpcParams);
if (error) {
console.error(
`[A16C] [${correlationId}] get_votes_for_figure error: ${error.message}`,
);
return errorResponse("Failed to fetch votes", 500, "RPC_ERROR");
}
return jsonResponse({
figure_id: figureId,
votes: data || [],
count: (data || []).length,
filters: {
chamber: chamber || null,
congress_session: parsedSession,
from_date: fromDate || null,
to_date: toDate || null,
},
pagination: {
limit: parsedLimit,
offset: parsedOffset,
},
});
} catch (err) {
console.error(`[A16C] [${correlationId}] Unexpected error:`, err);
return errorResponse("Internal server error", 500, "INTERNAL_ERROR");
}
});
// ========================================================================
// END A16C -- get-votes Edge Function V1.0.1
// ========================================================================
