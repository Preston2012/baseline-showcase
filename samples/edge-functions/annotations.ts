// ========================================================================
// BASELINE V1.4 — ANNOTATIONS CRUD ENDPOINT
// A15B — V1.0.1
//
// FIXES APPLIED (V1.0.0 → V1.0.1 — GPT + Grok audit reconciliation):
// FIX1: Log config fetch errors before falling back to default quota.
// Aids diagnosis when paid users are stuck at free quota. [Grok M1]
//
// PURPOSE:
// HTTP endpoint for annotation CRUD operations. Wraps A15A's RPCs with
// auth, feature gating (ENABLE_ANNOTATIONS), and tier quota enforcement
// (max_annotations from A13B config).
//
// DEPENDENCIES:
// - A1 V8.0 deployed (annotations table, RLS)
// - A13A V1.0.2 deployed (user auth, get_my_tier)
// - A13B V1.0.1 deployed (check_feature_access, get_feature_config)
// - A15A V1.0.1 deployed (all annotation RPCs)
//
// WHAT THIS DOES NOT DO:
// - Does not enforce rate limits (A17D middleware handles that)
// - Does not manage subscriptions (A17A/B handles that)
//
// ENDPOINT:
// POST /annotations
// Body: {
// "action": "create" | "update" | "delete" | "list" | "count",
// ...action-specific params
// }
//
// Actions:
// create: { action: "create", statement_id: UUID, note: string }
// → { annotation_id, action: "created" }
// update: { action: "update", annotation_id: UUID, note: string }
// → { success: true, action: "updated" }
// delete: { action: "delete", annotation_id: UUID }
// → { success: true, action: "deleted" }
// list: { action: "list", figure_id?: UUID, limit?: int, offset?: int }
// → { annotations: [...], count: N }
// count: { action: "count" }
// → { count: N, quota: N, remaining: N }
//
// SECURITY:
// - Requires authenticated user (JWT via Authorization header)
// - JWT verified via supabase.auth.getUser()
// - Feature-gated via check_feature_access('ENABLE_ANNOTATIONS')
// - Quota enforced on create: current count vs max_annotations config
// - All A15A RPCs are SECURITY INVOKER — RLS filters apply
//
// QUOTA MODEL (deny-by-default):
// - Default quota: 5 (free tier, from A13B seed)
// - If config fetch fails, cap at 5 (safe default)
// - Quota checked BEFORE create, not after
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
const FEATURE_FLAG = "ENABLE_ANNOTATIONS";
const FREE_DEFAULT_QUOTA = 5;
const VALID_ACTIONS = new Set(["create", "update", "delete", "list", "count"]);
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
function parseMaxAnnotations(featureConfig: unknown): number | null {
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
const rawMax = cfg.max_annotations;
const parsed = typeof rawMax === "number" ? rawMax : Number(rawMax);
if (Number.isInteger(parsed) && parsed > 0) {
return parsed;
}
return null;
}
// ── Action handlers──────────────────────────────────────────────────────────
async function handleCreate(
supabase: ReturnType<typeof createClient>,
body: Record<string, unknown>,
quota: number
): Promise<Response> {
const { statement_id, note } = body;
// Validate inputs
if (!statement_id) {
return errorResponse("statement_id is required", 400, "MISSING_STATEMENT_ID");
}
if (!isValidUUID(statement_id)) {
return errorResponse("statement_id must be a valid UUID", 400,
"INVALID_STATEMENT_ID");
}
if (!note || typeof note !== "string" || note.trim() === "") {
return errorResponse("note is required and cannot be empty", 400, "MISSING_NOTE");
}
if (note.length > 2000) {
return errorResponse("note exceeds 2000 character limit", 400, "NOTE_TOO_LONG");
}
// Check quota before creating
const { data: currentCount, error: countError } = await supabase.rpc(
"get_my_annotation_count"
);
if (countError) {
console.error("A15B: get_my_annotation_count error:", countError.message);
return errorResponse("Failed to check annotation quota", 500, "QUOTA_CHECK_ERROR");
}
if (currentCount >= quota) {
return errorResponse(
`Annotation limit reached (${quota}). Upgrade your plan for more.`,
403,
"QUOTA_EXCEEDED"
);
}
// Create annotation
const { data: annotationId, error: createError } = await supabase.rpc(
"upsert_annotation",
{ p_statement_id: statement_id, p_note: note }
);
if (createError) {
console.error("A15B: upsert_annotation error:", createError.message);
if (createError.message?.includes("not found or not accessible")) {
return errorResponse("Statement not found or not accessible", 404,
"STATEMENT_NOT_FOUND");
}
return errorResponse("Failed to create annotation", 500, "CREATE_ERROR");
}
return jsonResponse({ annotation_id: annotationId, action: "created" }, 201);
}
async function handleUpdate(
supabase: ReturnType<typeof createClient>,
body: Record<string, unknown>
): Promise<Response> {
const { annotation_id, note } = body;
// Validate inputs
if (!annotation_id) {
return errorResponse("annotation_id is required", 400, "MISSING_ANNOTATION_ID");
}
if (!isValidUUID(annotation_id)) {
return errorResponse("annotation_id must be a valid UUID", 400,
"INVALID_ANNOTATION_ID");
}
if (!note || typeof note !== "string" || note.trim() === "") {
return errorResponse("note is required and cannot be empty", 400, "MISSING_NOTE");
}
if (note.length > 2000) {
return errorResponse("note exceeds 2000 character limit", 400, "NOTE_TOO_LONG");
}
const { data: success, error: updateError } = await supabase.rpc(
"update_annotation",
{ p_annotation_id: annotation_id, p_note: note }
);
if (updateError) {
console.error("A15B: update_annotation error:", updateError.message);
if (updateError.message?.includes("not found or not owned")) {
return errorResponse("Annotation not found or not owned by user", 404,
"ANNOTATION_NOT_FOUND");
}
return errorResponse("Failed to update annotation", 500, "UPDATE_ERROR");
}
return jsonResponse({ success: true, action: "updated" });
}
async function handleDelete(
supabase: ReturnType<typeof createClient>,
body: Record<string, unknown>
): Promise<Response> {
const { annotation_id } = body;
// Validate inputs
if (!annotation_id) {
return errorResponse("annotation_id is required", 400, "MISSING_ANNOTATION_ID");
}
if (!isValidUUID(annotation_id)) {
return errorResponse("annotation_id must be a valid UUID", 400,
"INVALID_ANNOTATION_ID");
}
const { data: success, error: deleteError } = await supabase.rpc(
"delete_annotation",
{ p_annotation_id: annotation_id }
);
if (deleteError) {
console.error("A15B: delete_annotation error:", deleteError.message);
if (deleteError.message?.includes("not found or already deleted")) {
return errorResponse("Annotation not found or already deleted", 404,
"ANNOTATION_NOT_FOUND");
}
return errorResponse("Failed to delete annotation", 500, "DELETE_ERROR");
}
return jsonResponse({ success: true, action: "deleted" });
}
async function handleList(
supabase: ReturnType<typeof createClient>,
body: Record<string, unknown>
): Promise<Response> {
const { figure_id, limit: rawLimit, offset: rawOffset } = body;
// Validate optional figure_id
if (figure_id !== undefined && figure_id !== null) {
if (!isValidUUID(figure_id)) {
return errorResponse("figure_id must be a valid UUID", 400, "INVALID_FIGURE_ID");
}
}
// Validate limit/offset
let limit = 20;
if (rawLimit !== undefined && rawLimit !== null) {
if (typeof rawLimit !== "number" || !Number.isInteger(rawLimit) || rawLimit < 1) {
return errorResponse("limit must be a positive integer", 400, "INVALID_LIMIT");
}
limit = Math.min(rawLimit, 100);
}
let offset = 0;
if (rawOffset !== undefined && rawOffset !== null) {
if (typeof rawOffset !== "number" || !Number.isInteger(rawOffset) || rawOffset < 0) {
return errorResponse("offset must be a non-negative integer", 400, "INVALID_OFFSET");
}
offset = rawOffset;
}
const rpcParams: Record<string, unknown> = {
p_limit: limit,
p_offset: offset,
};
if (figure_id) {
rpcParams.p_figure_id = figure_id;
}
const { data: annotations, error: listError } = await supabase.rpc(
"get_my_annotations",
rpcParams
);
if (listError) {
console.error("A15B: get_my_annotations error:", listError.message);
return errorResponse("Failed to retrieve annotations", 500, "LIST_ERROR");
}
const resultList = annotations ?? [];
return jsonResponse({
annotations: resultList,
count: resultList.length,
});
}
async function handleCount(
supabase: ReturnType<typeof createClient>,
quota: number
): Promise<Response> {
const { data: count, error: countError } = await supabase.rpc(
"get_my_annotation_count"
);
if (countError) {
console.error("A15B: get_my_annotation_count error:", countError.message);
return errorResponse("Failed to get annotation count", 500, "COUNT_ERROR");
}
const currentCount = count ?? 0;
return jsonResponse({
count: currentCount,
quota,
remaining: Math.max(0, quota - currentCount),
});
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
const { action } = body;
// ── Validate action────────────────────────────────────────────────────
if (!action || typeof action !== "string") {
return errorResponse("action is required", 400, "MISSING_ACTION");
}
if (!VALID_ACTIONS.has(action)) {
return errorResponse(
`Invalid action: ${action}. Must be one of: ${[...VALID_ACTIONS].join(", ")}`,
400,
"INVALID_ACTION"
);
}
// ── Initialize Supabase client with user's JWT ─────────────────────────
const authHeader = req.headers.get("Authorization");
if (!authHeader) {
return errorResponse("Authorization header required", 401, "UNAUTHORIZED");
}
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
if (!supabaseUrl || !supabaseAnonKey) {
console.error("A15B: Missing SUPABASE_URL or SUPABASE_ANON_KEY");
return errorResponse("Server configuration error", 500, "CONFIG_ERROR");
}
const supabase = createClient(supabaseUrl, supabaseAnonKey, {
global: { headers: { Authorization: authHeader } },
});
// ── Verify JWT resolves to a user──────────────────────────────────────
const { data: userData, error: userError } =
await supabase.auth.getUser();
if (userError || !userData?.user) {
return errorResponse("Invalid or expired token", 401, "UNAUTHORIZED");
}
// ── Check feature access───────────────────────────────────────────────
const [accessResult, configResult] = await Promise.all([
supabase.rpc("check_feature_access", { p_flag_name: FEATURE_FLAG }),
supabase.rpc("get_feature_config", { p_flag_name: FEATURE_FLAG }),
]);
if (accessResult.error) {
console.error("A15B: check_feature_access error:", accessResult.error.message);
return errorResponse("Failed to check feature access", 500,
"FEATURE_CHECK_ERROR");
}
if (!accessResult.data) {
return errorResponse(
"Annotations are not available for your current plan",
403,
"FEATURE_GATED"
);
}
// ── Resolve quota (deny-by-default)────────────────────────────────────
// V1.0.1 FIX1: Log config errors for observability
if (configResult.error) {
console.error("A15B: get_feature_config error:", configResult.error.message);
}
const tierQuota = parseMaxAnnotations(configResult.data);
const quota = tierQuota !== null
? tierQuota
: FREE_DEFAULT_QUOTA;
// ── Dispatch to action handler─────────────────────────────────────────
switch (action) {
case "create":
return await handleCreate(supabase, body, quota);
case "update":
return await handleUpdate(supabase, body);
case "delete":
return await handleDelete(supabase, body);
case "list":
return await handleList(supabase, body);
case "count":
return await handleCount(supabase, quota);
default:
return errorResponse("Invalid action", 400, "INVALID_ACTION");
}
} catch (err) {
console.error("A15B: Unexpected error:", err);
return errorResponse("Internal server error", 500, "INTERNAL_ERROR");
}
});
