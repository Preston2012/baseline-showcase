// ========================================================================
// BASELINE V1.4 — GET-RECEIPT ENDPOINT
// A14B — V1.0.1
//
// FIXES APPLIED (V1.0.0 → V1.0.1 — GPT + Grok audit reconciliation):
// FIX1: Deny-by-default limit cap. DEFAULT_LIMIT = 3 (free cap).
// Only expands if tier config explicitly allows more. Prevents
// free users getting 5 results on config fetch failure. [Grok C1]
// FIX2: JWT verification via supabase.auth.getUser(). Returns clean
// 401 if token is invalid/expired. [Grok H1]
// FIX3: Robust config parsing — handles string or object featureConfig,
// safe Number() conversion with fallback. [Grok M1]
// FIX4: Statement-not-found detection via empty result instead of
// brittle string matching on error messages. [Grok M2 + GPT]
// FIX5: Parallel RPC calls — check_feature_access and get_feature_config
// run via Promise.all to reduce latency. [GPT]
//
// PURPOSE:
// HTTP endpoint wrapping A1's get_receipt() RPC. Returns semantically
// similar past statements for a given statement (The Receipt™).
// Tier-gated: free users get max 3 results, paid users get 5.
//
// DEPENDENCIES:
// - A1 V8.0 deployed (get_receipt RPC, statements with embeddings)
// - A13A V1.0.2 deployed (user auth, get_my_tier)
// - A13B V1.0.1 deployed (check_feature_access, get_feature_config)
//
// WHAT THIS DOES NOT DO:
// - Does not compute embeddings (A4 does that)
// - Does not enforce rate limits (A17D middleware handles that)
// - Does not modify any data (read-only)
//
// ENDPOINT:
// POST /get-receipt
// Body: { "statement_id": "uuid", "limit": 5 }
// Returns: { "statement_id": "...", "receipts": [...], "count": N }
//
// SECURITY:
// - Requires authenticated user (JWT via Authorization header)
// - JWT verified via supabase.auth.getUser()
// - Feature-gated via check_feature_access('ENABLE_RECEIPT')
// - Limit capped by tier config (max_results from tier_features)
// - Deny-by-default: cap is 3 unless config explicitly grants more
// - get_receipt() RPC is SECURITY INVOKER — RLS filters apply
//
// ========================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// ── CORS headers─────────────────────────────────────────────────────────────
const CORS_HEADERS = {
"Access-Control-Allow-Origin": "*",
"Access-Control-Allow-Headers":
"authorization, x-client-info, apikey, content-type",
"Access-Control-Allow-Methods": "POST, OPTIONS",
};
// ── Constants────────────────────────────────────────────────────────────────
const FEATURE_FLAG = "ENABLE_RECEIPT";
// V1.0.1 FIX1: Deny-by-default — free tier cap applied unless config expands
const FREE_DEFAULT_CAP = 3;
const DEFAULT_LIMIT = FREE_DEFAULT_CAP;
const ABSOLUTE_MAX_LIMIT = 5; // Hard cap from A1's get_receipt() RPC
// ── UUID validation──────────────────────────────────────────────────────────
const UUID_REGEX =
/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isValidUUID(value: unknown): value is string {
return typeof value === "string" && UUID_REGEX.test(value);
}
// ── JSON response helper─────────────────────────────────────────────────────
function jsonResponse(body: Record<string, unknown>, status = 200): Response {
return new Response(JSON.stringify(body), {
status,
headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
});
}
// ── Error response helper────────────────────────────────────────────────────
function errorResponse(
message: string,
status: number,
code?: string
): Response {
return jsonResponse(
{ error: message, ...(code ? { code } : {}) },
status
);
}
// ── Config parser helper─────────────────────────────────────────────────────
// V1.0.1 FIX3: Handles string or object featureConfig from Supabase RPC
function parseMaxResults(featureConfig: unknown): number | null {
if (!featureConfig) return null;
let cfg: Record<string, unknown> | null = null;
if (typeof featureConfig === "string") {
try {
cfg = JSON.parse(featureConfig);
} catch {
return null;
}
} else if (typeof featureConfig === "object") {
cfg = featureConfig as Record<string, unknown>;
}
if (!cfg) return null;
const rawMax = cfg.max_results;
const parsed = typeof rawMax === "number" ? rawMax : Number(rawMax);
if (Number.isInteger(parsed) && parsed > 0) {
return parsed;
}
return null;
}
// ── Main handler─────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
// Handle CORS preflight
if (req.method === "OPTIONS") {
return new Response("ok", { headers: CORS_HEADERS });
}
// POST only
if (req.method !== "POST") {
return errorResponse("Method not allowed", 405, "METHOD_NOT_ALLOWED");
}

const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
if (killswitchActive) {
  return jsonResponse({ error: "Service temporarily unavailable", reason: "maintenance" }, 503);
}

try {
// ── Parse request body─────────────────────────────────────────────────
let body: Record<string, unknown>;
try {
body = await req.json();
} catch {
return errorResponse("Invalid JSON body", 400, "INVALID_JSON");
}
const { statement_id, limit: requestedLimit } = body;
// ── Validate statement_id──────────────────────────────────────────────
if (!statement_id) {
return errorResponse(
"statement_id is required",
400,
"MISSING_STATEMENT_ID"
);
}
if (!isValidUUID(statement_id)) {
return errorResponse(
"statement_id must be a valid UUID",
400,
"INVALID_STATEMENT_ID"
);
}
// ── Validate limit (optional)──────────────────────────────────────────
let limit = DEFAULT_LIMIT;
if (requestedLimit !== undefined && requestedLimit !== null) {
if (
typeof requestedLimit !== "number" ||
!Number.isInteger(requestedLimit) ||
requestedLimit < 1
) {
return errorResponse(
"limit must be a positive integer",
400,
"INVALID_LIMIT"
);
}
limit = Math.min(requestedLimit, ABSOLUTE_MAX_LIMIT);
}
// ── Initialize Supabase client with user's JWT ─────────────────────────
const authHeader = req.headers.get("Authorization");
if (!authHeader) {
return errorResponse(
"Authorization header required",
401,
"UNAUTHORIZED"
);
}
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
if (!supabaseUrl || !supabaseAnonKey) {
console.error("A14B: Missing SUPABASE_URL or SUPABASE_ANON_KEY");
return errorResponse("Server configuration error", 500, "CONFIG_ERROR");
}
const supabase = createClient(supabaseUrl, supabaseAnonKey, {
global: { headers: { Authorization: authHeader } },
});
// ── V1.0.1 FIX2: Verify JWT resolves to a user ────────────────────────
const { data: userData, error: userError } =
await supabase.auth.getUser();
if (userError || !userData?.user) {
return errorResponse(
"Invalid or expired token",
401,
"UNAUTHORIZED"
);
}
// ── V1.0.1 FIX5: Parallel feature access + config check ───────────────
const [accessResult, configResult] = await Promise.all([
supabase.rpc("check_feature_access", { p_flag_name: FEATURE_FLAG }),
supabase.rpc("get_feature_config", { p_flag_name: FEATURE_FLAG }),
]);
// ── Check feature access───────────────────────────────────────────────
if (accessResult.error) {
console.error(
"A14B: check_feature_access error:",
accessResult.error.message
);
return errorResponse(
"Failed to check feature access",
500,
"FEATURE_CHECK_ERROR"
);
}
if (!accessResult.data) {
return errorResponse(
"The Receipt is not available for your current plan",
403,
"FEATURE_GATED"
);
}
// ── V1.0.1 FIX1 + FIX3: Apply tier cap (deny-by-default) ──────────────
const tierMax = parseMaxResults(configResult.data);
if (tierMax !== null) {
// Config found — cap to tier's max_results (and absolute max)
limit = Math.min(limit, Math.min(tierMax, ABSOLUTE_MAX_LIMIT));
} else {
// Config missing or unparseable — enforce safe free-tier cap
limit = Math.min(limit, FREE_DEFAULT_CAP);
}
// ── Call get_receipt() RPC──────────────────────────────────────────────
const { data: receipts, error: receiptError } = await supabase.rpc(
"get_receipt",
{
p_statement_id: statement_id,
p_limit: limit,
}
);
if (receiptError) {
console.error("A14B: get_receipt error:", receiptError.message);
return errorResponse(
"Failed to retrieve receipts",
500,
"RECEIPT_ERROR"
);
}
// ── V1.0.1 FIX4: Check for empty result (statement not found / no matches)
// Instead of parsing error message strings, treat null/empty as valid.
// A missing statement returns empty from get_receipt() due to RLS.
const resultList = receipts ?? [];
// ── Return results─────────────────────────────────────────────────────
return jsonResponse({
statement_id,
receipts: resultList,
count: resultList.length,
});
} catch (err) {
console.error("A14B: Unexpected error:", err);
return errorResponse("Internal server error", 500, "INTERNAL_ERROR");
}
});
