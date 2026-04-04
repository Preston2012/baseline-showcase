// ========================================================================
// BASELINE V1.4 — Edge Function: manual-ingest-trigger (A5B FINAL v1.4.3)
// Deploy to: supabase/functions/manual-ingest-trigger/index.ts
// ========================================================================
// Changes from v1.4.2:
// - BLOCKER FIX: Removed office-account remapping (offices are separate figures)
// - BLOCKER FIX: Match allowlist by figure.allowlist_id instead of name
// - HIGH FIX: X/Twitter detection is hostname-based, allows /i/web/status/
// - Documented: Pattern matching is intentionally case-insensitive
//
// Guarantees (locked intent):
// - Packet 06 FILTER WALL: allowlist enforcement occurs BEFORE any DB write
// - Packet 01: GLOBAL KILLSWITCH halts ingestion valve (prevents queue fill incidents)
// - URL canonicalization before allowlist + before dedupe insert
// - Input caps: raw_text <= 50,000 chars, whitespace-only rejected
// - UUID + URL + timestamp reasonableness validation
// - Sanitized errors + helpful duplicate diagnostics
//
// DESIGN DECISIONS:
// - Office accounts (@POTUS, @VP, @WhiteHouse) are separate figures in DB
// - Statements from @POTUS stay attributed to "Office of the President" forever
// - No remapping on administration change — immutable attribution
// - Pattern matching is case-insensitive (intentional for URL/handle matching)
//
// STATE MACHINE (A5A contract):
// - This function inserts with status='pending'
// - A5C sets status='processing' before calling persist_gemini_output
// - persist_gemini_output sets status='completed'/'skipped'/'failed'
//
// DEPENDENCIES:
// - A0: Allowlist JSON with figures[].id matching DB figures.allowlist_id
// - A1: figures table with allowlist_id column
// - A5A: raw_ingestion_jobs table
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY =
Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const INGEST_AUTH_TOKEN = Deno.env.get("INGEST_AUTH_TOKEN") || "";
const MAX_RAW_TEXT_LENGTH = 50000;
const MAX_URL_LENGTH = 2048;
const ALLOWED_SOURCE_TYPES = new Set([
"official_site",
"verified_social",
"transcript",
"clip",
]);
const UUID_REGEX =
/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// X/Twitter hostnames (exhaustive list for hostname-based detection)
const X_HOSTNAMES = new Set([
"x.com",
"www.x.com",
"twitter.com",
"www.twitter.com",
"mobile.twitter.com",
"m.twitter.com",
]);
// Kill switch startup log (debugging aid, matches A4 pattern)
const BASELINE_KILL_SWITCH_RAW = Deno.env.get("BASELINE_KILL_SWITCH") || "";
console.log("A5B manual-ingest-trigger startup", {
BASELINE_KILL_SWITCH: BASELINE_KILL_SWITCH_RAW || "(not set)",
});
// -------------------------- helpers --------------------------
function jsonResponse(status: number, payload: Record<string, unknown>) {
return new Response(JSON.stringify(payload), {
status,
headers: { "Content-Type": "application/json" },
});
}
function parseKillswitch(): boolean {
const v = BASELINE_KILL_SWITCH_RAW.trim();
return v === "TRUE" || v.toLowerCase() === "true";
}
function canonicalizeUrl(input: string): string {
// Canonicalization rules (security + dedupe):
// - force https
// - lowercase hostname
// - remove default ports
// - normalize repeated slashes in pathname
// - strip query params entirely (prevents utm/evasion + dedupe stability)
// - strip hash fragment
// - remove trailing slash (except root)
const u = new URL(input);
u.protocol = "https:";
u.hostname = u.hostname.toLowerCase();
if (u.port === "443" || u.port === "80") u.port = "";
u.hash = "";
u.search = ""; // strip ALL query params
let p = u.pathname.replace(/\/{2,}/g, "/");
if (p.length > 1 && p.endsWith("/")) p = p.slice(0, -1);
u.pathname = p;
return u.toString();
}
function likePatternToRegex(pattern: string): RegExp {
// Convert SQL LIKE-ish patterns to regex safely:
// - Escape regex metachars
// - % => .*
// - _ => .
// NOTE: Case-insensitive matching is intentional for URL/handle matching
const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const regexBody = escaped.replace(/%/g, ".*").replace(/_/g, ".");
return new RegExp(`^${regexBody}$`, "i");
}
function isXDomain(url: string): boolean {
// Hostname-based detection (more robust than substring)
try {
const hostname = new URL(url).hostname.toLowerCase();
return X_HOSTNAMES.has(hostname);
} catch {
return false;
}
}
function isValidXStatusUrl(url: string): boolean {
// Accept:
// - /status/{id}
// - /statuses/{id}
// - /i/web/status/{id}
try {
const pathname = new URL(url).pathname;
return /\/(status|statuses)\/\d+$/i.test(pathname) ||
/\/i\/web\/status\/\d+$/i.test(pathname);
} catch {
return false;
}
}
// -------------------------- allowlist loading (A0) --------------------------
// Supports either:
// - ALLOWLIST_JSON_INLINE : env var containing the full JSON string, OR
// - ALLOWLIST_JSON_PATH : file path inside the function bundle/container
type AllowlistFigure = {
id: string; // Matches DB figures.allowlist_id
name: string;
allowlist_patterns?: string[];
};
type AllowlistConfig = {
figures?: AllowlistFigure[];
};
let allowlistCache: { loadedAt: number; data: AllowlistConfig | null } = {
loadedAt: 0,
data: null,
};
async function loadAllowlist(): Promise<AllowlistConfig> {
const now = Date.now();
if (allowlistCache.data && now - allowlistCache.loadedAt < 60_000) {
return allowlistCache.data;
}
const inline = Deno.env.get("ALLOWLIST_JSON_INLINE");
const path = Deno.env.get("ALLOWLIST_JSON_PATH");
let parsed: AllowlistConfig | null = null;
try {
if (inline && inline.trim().length > 0) {
parsed = JSON.parse(inline);
} else if (path && path.trim().length > 0) {
const txt = await Deno.readTextFile(path);
parsed = JSON.parse(txt);
} else {
throw new Error("Missing ALLOWLIST_JSON_INLINE or ALLOWLIST_JSON_PATH");
}
} catch (e: any) {
console.error("CRITICAL: allowlist load failed", { message: e?.message });
throw new Error("ALLOWLIST_LOAD_FAILED");
}
allowlistCache = { loadedAt: now, data: parsed };
return parsed;
}
function urlMatchesPatterns(
canonicalUrl: string,
patterns: string[] | undefined,
badPatternSink?: (p: string) => void
): boolean {
if (!patterns || patterns.length === 0) return false;
for (const p of patterns) {
try {
const re = likePatternToRegex(p);
if (re.test(canonicalUrl)) return true;
} catch {
if (badPatternSink) badPatternSink(p);
}
}
return false;
}
// ========================================================================
// handler
// ========================================================================
serve(async (req: Request) => {
// --------------------------------------------------------------------------
// CORS preflight
// --------------------------------------------------------------------------
if (req.method === "OPTIONS") {
return new Response("ok", {
headers: {
"Access-Control-Allow-Origin": "*",
"Access-Control-Allow-Headers":
"authorization, x-client-info, apikey, content-type",
"Access-Control-Allow-Methods": "POST, OPTIONS",
},
});
}
if (req.method !== "POST") {
return jsonResponse(405, { error: "Method not allowed" });
}
// ------------------------------------------------------------------------
// Auth check (robust header casing)
// ------------------------------------------------------------------------
const authHeader =
req.headers.get("Authorization") || req.headers.get("authorization");
if (!authHeader || authHeader !== `Bearer ${INGEST_AUTH_TOKEN}`) {
return jsonResponse(401, { error: "Unauthorized" });
}
// ------------------------------------------------------------------------
// KILLSWITCH check (Packet 01: emergency halt)
// ------------------------------------------------------------------------
if (parseKillswitch()) {
return jsonResponse(503, {
error: "Service temporarily unavailable (emergency halt active)",
killswitch: true,
});
}
// ------------------------------------------------------------------------
// Parse JSON body safely
// ------------------------------------------------------------------------
let body: any;
try {
body = await req.json();
} catch {
return jsonResponse(400, { error: "Invalid JSON body" });
}
// Inputs
const figureId = typeof body.figure_id === "string" ? body.figure_id.trim() : "";
const sourceUrlRaw =
typeof body.source_url === "string" ? body.source_url.trim() : "";
const sourceType =
typeof body.source_type === "string" ? body.source_type.trim() : "";
const rawText = typeof body.raw_text === "string" ? body.raw_text : "";
const submittedBy =
typeof body.submitted_by === "string" && body.submitted_by.trim().length > 0
? body.submitted_by.trim()
: "manual";
const timestamp = body.timestamp;
// ------------------------------------------------------------------------
// Required fields
// ------------------------------------------------------------------------
if (!figureId || !sourceUrlRaw || !sourceType || !rawText || !timestamp) {
return jsonResponse(400, {
error:
"Missing required fields: figure_id, source_url, source_type, raw_text, timestamp",
});
}
// ------------------------------------------------------------------------
// source_type validation
// ------------------------------------------------------------------------
if (!ALLOWED_SOURCE_TYPES.has(sourceType)) {
return jsonResponse(400, {
error: `Invalid source_type. Must be one of: ${Array.from(
ALLOWED_SOURCE_TYPES
).join(", ")}`,
});
}
// ------------------------------------------------------------------------
// UUID format validation (figure_id)
// ------------------------------------------------------------------------
if (!UUID_REGEX.test(figureId)) {
return jsonResponse(400, { error: "figure_id must be valid UUID format" });
}
// ------------------------------------------------------------------------
// raw_text cap + whitespace-only rejection
// ------------------------------------------------------------------------
const trimmed = rawText.trim();
if (trimmed.length === 0) {
return jsonResponse(400, { error: "raw_text is empty or whitespace-only" });
}
if (trimmed.length > MAX_RAW_TEXT_LENGTH) {
return jsonResponse(400, {
error: `raw_text exceeds maximum length of ${MAX_RAW_TEXT_LENGTH} characters`,
actual_length: trimmed.length,
});
}
// ------------------------------------------------------------------------
// URL length cap before parsing
// ------------------------------------------------------------------------
if (sourceUrlRaw.length > MAX_URL_LENGTH) {
return jsonResponse(400, {
error: `source_url exceeds maximum length of ${MAX_URL_LENGTH} characters`,
});
}
// ------------------------------------------------------------------------
// URL format validation + canonicalization
// ------------------------------------------------------------------------
try {
const parsedUrl = new URL(sourceUrlRaw);
if (!["http:", "https:"].includes(parsedUrl.protocol)) {
throw new Error("Protocol must be http or https");
}
} catch (err: any) {
return jsonResponse(400, {
error: `Invalid source_url: ${err?.message || "malformed URL"}`,
});
}
let canonicalUrl: string;
try {
canonicalUrl = canonicalizeUrl(sourceUrlRaw);
} catch {
return jsonResponse(400, {
error: "Invalid source_url (canonicalization failed)",
});
}
// ------------------------------------------------------------------------
// Timestamp validation (ISO 8601 + reasonableness)
// ------------------------------------------------------------------------
const parsedTimestamp = new Date(timestamp);
if (isNaN(parsedTimestamp.getTime())) {
return jsonResponse(400, {
error:
"Invalid timestamp. Must be valid ISO 8601 (e.g., 2026-01-31T12:34:56Z)",
});
}
const now = new Date();
const oneDayFuture = new Date(now.getTime() + 86400000); // +24h
const year1900 = new Date("1900-01-01T00:00:00Z");
if (parsedTimestamp > oneDayFuture) {
return jsonResponse(400, {
error: `Timestamp is in future: ${parsedTimestamp.toISOString()} (current:
${now.toISOString()})`,
});
}
if (parsedTimestamp < year1900) {
return jsonResponse(400, {
error: `Timestamp is suspiciously old: ${parsedTimestamp.toISOString()}`,
});
}
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
// ------------------------------------------------------------------------
// Verify figure exists and is active (fetch allowlist_id for matching)
// ------------------------------------------------------------------------
const { data: figure, error: figureError } = await supabase
.from("figures")
.select("figure_id, name, allowlist_id, is_active")
.eq("figure_id", figureId)
.single();
if (figureError || !figure || figure.is_active !== true) {
return jsonResponse(404, { error: "Figure not found or not active" });
}
if (!figure.allowlist_id) {
console.error("Figure missing allowlist_id", {
figure_id: figure.figure_id,
name: figure.name,
});
return jsonResponse(500, {
error: "Figure configuration error: missing allowlist_id",
});
}
// ------------------------------------------------------------------------
// ALLOWLIST ENFORCEMENT (CRITICAL: Packet 06 filter wall)
// Match by allowlist_id (stable key) instead of name (fragile)
// ------------------------------------------------------------------------
let allowlist: AllowlistConfig;
try {
allowlist = await loadAllowlist();
} catch {
return jsonResponse(500, {
error: "Allowlist configuration unavailable (service misconfigured)",
});
}
const badPatterns: string[] = [];
const recordBad = (p: string) => badPatterns.push(p);
// Find allowlist entry by id (matches figure.allowlist_id)
const figuresAllow = Array.isArray(allowlist.figures) ? allowlist.figures : [];
const figAllow = figuresAllow.find((f) => f?.id === figure.allowlist_id);
if (badPatterns.length > 0) {
console.warn("Allowlist contains malformed pattern(s)", {
patterns: badPatterns.slice(0, 10),
count: badPatterns.length,
});
}
if (!figAllow) {
console.error("Figure not found in allowlist", {
figure_id: figure.figure_id,
allowlist_id: figure.allowlist_id,
});
return jsonResponse(403, {
error: `Figure not found in allowlist (allowlist_id: ${figure.allowlist_id})`,
});
}
const allowed = urlMatchesPatterns(canonicalUrl, figAllow.allowlist_patterns, recordBad);
if (!allowed) {
console.warn("Allowlist rejection", {
figure_id: figure.figure_id,
allowlist_id: figure.allowlist_id,
source_url: canonicalUrl,
});
return jsonResponse(403, {
error: "Source URL not permitted for this figure (allowlist violation)",
canonical_url: canonicalUrl,
});
}
// X-specific: must be status URL (hostname-based detection)
if (isXDomain(canonicalUrl) && !isValidXStatusUrl(canonicalUrl)) {
return jsonResponse(403, {
error: "X/Twitter posts must use /status/{id} or /i/web/status/{id} format (post URLs only)",
canonical_url: canonicalUrl,
});
}
// ------------------------------------------------------------------------
// Insert ingestion job (store CANONICAL url)
// STATE MACHINE: Insert with status='pending' (A5A contract)
// ------------------------------------------------------------------------
const { data: job, error: jobError } = await supabase
.from("raw_ingestion_jobs")
.insert({
figure_id: figure.figure_id,
source_url: canonicalUrl,
source_type: sourceType,
raw_text: trimmed,
submitted_by: submittedBy,
source_timestamp: parsedTimestamp.toISOString(),
status: "pending",
})
.select("job_id, status")
.single();
if (jobError) {
console.error("Job creation failed", {
figure_id: figure.figure_id,
source_url: canonicalUrl,
code: (jobError as any).code,
message: jobError.message,
});
// 23505 = unique_violation (figure_id + source_url + source_hash)
if ((jobError as any).code === "23505") {
// IMPORTANT (A5A v1.4): there may be multiple rows per (figure_id, source_url)
// so we DO NOT use .single() here.
const { data: existing } = await supabase
.from("raw_ingestion_jobs")
.select("job_id, status, submitted_at, retry_count, max_retries, error_log")
.eq("figure_id", figure.figure_id)
.eq("source_url", canonicalUrl)
.order("submitted_at", { ascending: false })
.limit(1)
.maybeSingle();
return jsonResponse(409, {
error: "Duplicate: identical job already exists (figure + canonical_url + content hash)",
canonical_url: canonicalUrl,
existing_job_id: existing?.job_id,
existing_status: existing?.status,
existing_retry_count: existing?.retry_count,
existing_max_retries: existing?.max_retries,
hint:
existing?.status === "failed"
? "Previous identical job failed. Retry via A5C (increment retry_count/last_retry_at) or change raw_text/source_url if content truly differs."
: "If pending/processing is stuck, check A5C/A5D workers and queue health.",
});
}
return jsonResponse(500, { error: "Job creation failed (see server logs)" });
}
return jsonResponse(200, {
success: true,
job_id: job.job_id,
figure_id: figure.figure_id,
canonical_url: canonicalUrl,
message: "Ingestion job created. Proceed to Gemini structuring (A5C).",
});
});
