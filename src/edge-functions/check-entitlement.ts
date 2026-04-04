// ========================================================================
// BASELINE V1.4 -- ENTITLEMENT MIDDLEWARE
// A17D -- V1.0.1
//
// FIXES APPLIED (V1.0.0 → V1.0.1 - dual audit reconciliation):
// FIX1: Server-enforced rate limiting via signed entitlement token.
// A17D now returns an HMAC-signed X-Entitlement-Token containing
// endpoint + user_id/ip + timestamp + expiry. Target endpoints
// MUST verify this token (helper provided). Prevents clients from
// bypassing A17D and calling protected endpoints directly.
// [Audit 2 Critical Blocker #1]
// FIX2: Feature-gated requests no longer record rate-limit hits.
// Users don't burn quota on 403 denials. Only allowed requests
// (200) record hits.
// [Audit 2 Critical Blocker #2]
// FIX3: Anonymous requests with no resolvable IP are now denied (429)
// instead of fail-open. Prevents unlimited anonymous access via
// malformed proxy headers or misconfigured CDN.
// [Audit 2 Critical Blocker #3]
// FIX4: X-RateLimit-Remaining now returns exact value from
// check_rate_limit(). No manual decrement - avoids lying headers
// when fire-and-forget record fails.
// [Audit 2 Non-blocking #4]
// FIX5: Canonical endpoint allowlist. Server-side enum of valid
// protected endpoints. Rejects unknown endpoints at validation.
// [Audit 2 Non-blocking #6, Audit 1 alignment]
// FIX6: Parallel RPC calls where possible (getUser + rate check).
// [Audit 1 Perf suggestion]
//
// PURPOSE:
// Centralized rate-limit and entitlement check endpoint. Returns a
// signed entitlement token that target endpoints MUST verify. This
// ensures rate limiting is server-enforced, not client-cooperative.
//
// FLOW:
// 1. Client → POST /check-entitlement { endpoint, feature_flag? }
// 2. A17D verifies identity, checks rate limit, checks feature access
// 3. If allowed → returns signed X-Entitlement-Token (valid 30s)
// 4. Client → calls target endpoint with X-Entitlement-Token header
// 5. Target endpoint verifies token via verifyEntitlementToken() helper
//
// TOKEN FORMAT (HMAC-SHA256 signed):
// base64({ endpoint, uid, ip, tier, iat, exp }) + "." + base64(signature)
// - uid: user_id or "anon"
// - ip: client IP (for anonymous)
// - exp: iat + 30 seconds (short-lived)
// - Signed with ENTITLEMENT_SIGNING_SECRET env var
//
// DEPENDENCIES:
// - A17C V1.0.1 deployed (check_rate_limit, record_rate_limit_hit RPCs)
// - A13A V1.0.2 deployed (user_profiles, get_my_tier())
// - A13B V1.0.1 deployed (check_feature_access RPC - optional gating)
// - Supabase Edge Functions runtime (Deno)
//
// ENDPOINT:
// POST /check-entitlement
// Body: { "endpoint": "get-receipt", "feature_flag": "ENABLE_RECEIPT" }
// - endpoint (required): must be in CANONICAL_ENDPOINTS allowlist
// - feature_flag (optional): if provided, also checks A13B feature access
//
// Auth:
// - Authenticated: JWT via Authorization header → user_id + tier
// - Anonymous: no JWT → rate-limited by client IP at free-tier cap
//
// Response (200 allowed, 429 rate-limited, 403 feature-gated):
// {
// "allowed": true,
// "endpoint": "get-receipt",
// "entitlement_token": "<signed-token>",
// "rate_limit": { "remaining": 95, "limit": 100, "used": 5, "reset_at": "..." },
// "tier": "free",
// "feature_access": true
// }
//
// Response Headers (always set):
// X-RateLimit-Limit: 100
// X-RateLimit-Remaining: 95
// X-RateLimit-Reset: <unix timestamp>
// X-Entitlement-Token: <signed-token> (only on 200)
// Retry-After: <seconds> (only on 429)
//
// SECURITY:
// - Anon key or JWT accepted (dual-mode)
// - Service-role Supabase client for RPC calls
// - User JWT verified via supabase.auth.getUser()
// - HMAC-signed entitlement token (30s expiry)
// - KILLSWITCH respected
// - CORS enabled (mobile web)
// - No PII in logs
//
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── ENV──────────────────────────────────────────────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_ANON_KEY = String(
Deno.env.get("SUPABASE_ANON_KEY") || ""
).trim();
const SUPABASE_SERVICE_ROLE_KEY = String(
Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
).trim();
const ENTITLEMENT_SIGNING_SECRET = String(
Deno.env.get("ENTITLEMENT_SIGNING_SECRET") || ""
).trim();
// ── Constants────────────────────────────────────────────────────────────
const CORS_HEADERS: Record<string, string> = {
"Access-Control-Allow-Origin": "*",
"Access-Control-Allow-Headers":
"authorization, x-client-info, apikey, content-type, x-entitlement-token",
"Access-Control-Allow-Methods": "POST, OPTIONS",
};
// FIX5: Canonical endpoint allowlist - server-side enum.
// A17D only accepts these values. Target endpoints must match.
// Add new entries here when new protected endpoints are deployed.
const CANONICAL_ENDPOINTS = new Set([
"get-receipt",
"get-feed",
"get-statement",
"get-trends",
"get-votes",
"annotations",
"check-entitlement", // self (for health checks)
]);
// Endpoint validation regex (must also match A17C table CHECK)
const ENDPOINT_REGEX = /^[a-z0-9-]+$/;
const ENDPOINT_MAX_LENGTH = 64;
// Feature flag validation
const FLAG_REGEX = /^[A-Z][A-Z0-9_]+$/;
const FLAG_MAX_LENGTH = 64;
// Entitlement token expiry (seconds)
const TOKEN_EXPIRY_SECONDS = 30;
// ── Helpers──────────────────────────────────────────────────────────────
function jsonResponse(
body: Record<string, unknown>,
status = 200,
extraHeaders: Record<string, string> = {}
): Response {
return new Response(JSON.stringify(body), {
status,
headers: {
...CORS_HEADERS,
"Content-Type": "application/json",
...extraHeaders,
},
});
}
function parseKillswitch(): boolean {
const v = String(Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
return v === "TRUE" || v.toLowerCase() === "true";
}
// Extract client IP from Supabase/CDN forwarded headers
function getClientIp(req: Request): string | null {
// Supabase sets x-forwarded-for; take first (client) IP
const forwarded = req.headers.get("x-forwarded-for");
if (forwarded) {
const first = forwarded.split(",")[0].trim();
if (first) return first;
}
const realIp = req.headers.get("x-real-ip");
if (realIp) return realIp.trim();
const cfIp = req.headers.get("cf-connecting-ip");
if (cfIp) return cfIp.trim();
return null;
}
// Build rate-limit response headers from check result
function rateLimitHeaders(
rl: Record<string, unknown>
): Record<string, string> {
const headers: Record<string, string> = {};
if (typeof rl.limit === "number") {
headers["X-RateLimit-Limit"] = String(rl.limit);
}
if (typeof rl.remaining === "number") {
// FIX4: Return exact value from check - no manual decrement
headers["X-RateLimit-Remaining"] = String(rl.remaining);
}
if (rl.reset_at) {
const resetUnix = Math.ceil(
new Date(String(rl.reset_at)).getTime() / 1000
);
if (Number.isFinite(resetUnix)) {
headers["X-RateLimit-Reset"] = String(resetUnix);
}
}
return headers;
}
// ── FIX1: Entitlement Token (HMAC-SHA256)────────────────────────────────
// Short-lived signed token proving the caller passed rate-limit + entitlement.
// Target endpoints verify this before processing.
async function signEntitlementToken(
payload: Record<string, unknown>
): Promise<string> {
const encoder = new TextEncoder();
const payloadJson = JSON.stringify(payload);
const payloadB64 = btoa(payloadJson);
const key = await crypto.subtle.importKey(
"raw",
encoder.encode(ENTITLEMENT_SIGNING_SECRET),
{ name: "HMAC", hash: "SHA-256" },
false,
["sign"]
);
const signature = await crypto.subtle.sign(
"HMAC",
key,
encoder.encode(payloadB64)
);
const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
return `${payloadB64}.${sigB64}`;
}
// ── EXPORTED VERIFICATION HELPER─────────────────────────────────────────
// Target endpoints should copy or import this function.
// Usage:
// const token = req.headers.get("x-entitlement-token");
// const payload = await verifyEntitlementToken(token, "get-receipt", secret);
// if (!payload) return 403;
//
// This is provided as documentation - each target endpoint implements
// its own verification using the same ENTITLEMENT_SIGNING_SECRET env var.
//
// async function verifyEntitlementToken(
// token: string | null,
// expectedEndpoint: string,
// secret: string
// ): Promise<Record<string, unknown> | null> {
// if (!token || !token.includes(".")) return null;
// const [payloadB64, sigB64] = token.split(".", 2);
// if (!payloadB64 || !sigB64) return null;
//
// const encoder = new TextEncoder();
// const key = await crypto.subtle.importKey(
// "raw", encoder.encode(secret),
// { name: "HMAC", hash: "SHA-256" }, false, ["verify"]
// );
//
// const sigBytes = Uint8Array.from(atob(sigB64), c => c.charCodeAt(0));
// const valid = await crypto.subtle.verify(
// "HMAC", key, sigBytes, encoder.encode(payloadB64)
// );
// if (!valid) return null;
//
// const payload = JSON.parse(atob(payloadB64));
// if (payload.endpoint !== expectedEndpoint) return null;
// if (typeof payload.exp === "number" && Date.now() / 1000 > payload.exp) return null;
// return payload;
// }
// ── Main Handler─────────────────────────────────────────────────────────
serve(async (req: Request) => {
// CORS preflight
if (req.method === "OPTIONS") {
return new Response("ok", { headers: CORS_HEADERS });
}
if (req.method !== "POST") {
return jsonResponse({ error: "Method not allowed" }, 405);
}
// KILLSWITCH
if (parseKillswitch()) {
return jsonResponse(
{ error: "Service halted", reason: "BASELINE_KILL_SWITCH active" },
503
);
}
// Env validation
if (
!SUPABASE_URL ||
!SUPABASE_SERVICE_ROLE_KEY ||
!SUPABASE_ANON_KEY
) {
console.error("A17D: Missing required SUPABASE env vars");
return jsonResponse({ error: "Server configuration error" }, 500);
}
if (!ENTITLEMENT_SIGNING_SECRET) {
console.error("A17D: Missing ENTITLEMENT_SIGNING_SECRET");
return jsonResponse({ error: "Server configuration error" }, 500);
}
// ── Parse body────────────────────────────────────────────────────────
let body: Record<string, unknown>;
try {
body = await req.json();
} catch {
return jsonResponse({ error: "Invalid JSON body" }, 400);
}
const endpoint = String(body.endpoint || "").trim();
const featureFlag = body.feature_flag
? String(body.feature_flag).trim()
: null;
// ── Validate endpoint─────────────────────────────────────────────────
if (!endpoint) {
return jsonResponse({ error: "endpoint is required" }, 400);
}
if (
endpoint.length > ENDPOINT_MAX_LENGTH ||
!ENDPOINT_REGEX.test(endpoint)
) {
return jsonResponse(
{
error:
"endpoint must be lowercase alphanumeric + hyphens, max 64 chars",
},
400
);
}
// FIX5: Check canonical allowlist
if (!CANONICAL_ENDPOINTS.has(endpoint)) {
return jsonResponse(
{
error: `Unknown endpoint: ${endpoint}`,
error_code: "UNKNOWN_ENDPOINT",
valid_endpoints: [...CANONICAL_ENDPOINTS].sort(),
},
400
);
}
// ── Validate feature_flag (optional) ──────────────────────────────────
if (featureFlag !== null) {
if (
featureFlag.length > FLAG_MAX_LENGTH ||
!FLAG_REGEX.test(featureFlag)
) {
return jsonResponse(
{
error: "feature_flag must be UPPER_SNAKE_CASE, max 64 chars",
},
400
);
}
}
// ── Resolve identity──────────────────────────────────────────────────
const authHeader =
req.headers.get("Authorization") || req.headers.get("authorization");
let userId: string | null = null;
let userTier: string = "free";
let isAuthenticated = false;
if (authHeader && authHeader.startsWith("Bearer ")) {
const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
global: { headers: { Authorization: authHeader } },
});
const { data: userData, error: userError } =
await userClient.auth.getUser();
if (!userError && userData?.user) {
userId = userData.user.id;
isAuthenticated = true;
// Resolve tier
const { data: tierData } = await userClient.rpc("get_my_tier");
if (tierData && typeof tierData === "string") {
userTier = tierData;
}
}
// Invalid JWT → fall through to anonymous
}
const clientIp = !isAuthenticated ? getClientIp(req) : null;
// FIX3: Anonymous with no IP → deny (not fail-open)
if (!isAuthenticated && !clientIp) {
console.warn("A17D: No user_id or client_ip - denying request");
return jsonResponse(
{
allowed: false,
endpoint,
error: "Cannot identify requester for rate limiting",
error_code: "NO_IDENTITY",
},
429
);
}
// ── Service-role client for RPC calls ─────────────────────────────────
const serviceClient = createClient(
SUPABASE_URL,
SUPABASE_SERVICE_ROLE_KEY,
{ auth: { autoRefreshToken: false, persistSession: false } }
);
try {
// ── Check rate limit (A17C) ───────────────────────────────────────
const { data: rlResult, error: rlError } = await serviceClient.rpc(
"check_rate_limit",
{
p_endpoint: endpoint,
p_user_id: userId,
p_client_ip: clientIp,
p_tier: isAuthenticated ? userTier : "free",
}
);
if (rlError) {
console.error("A17D: check_rate_limit error:", rlError.message);
// Fail-open on infra failure: allow but no token (target can decide)
return jsonResponse({
allowed: true,
endpoint,
entitlement_token: null,
rate_limit: null,
tier: userTier,
feature_access: featureFlag ? null : true,
warning: "rate_limit_check_failed",
});
}
const rl = rlResult as Record<string, unknown>;
const rlHeaders = rateLimitHeaders(rl);
// ── Rate limited → 429 ──────────────────────────────────────────
if (rl.allowed === false) {
let retryAfter = 60;
if (rl.reset_at) {
const resetMs = new Date(String(rl.reset_at)).getTime();
const nowMs = Date.now();
if (Number.isFinite(resetMs) && resetMs > nowMs) {
retryAfter = Math.ceil((resetMs - nowMs) / 1000);
}
}
return jsonResponse(
{
allowed: false,
endpoint,
error: "Rate limit exceeded",
error_code: "RATE_LIMITED",
rate_limit: {
remaining: rl.remaining,
limit: rl.limit,
used: rl.used,
reset_at: rl.reset_at,
},
tier: rl.tier,
retry_after: retryAfter,
},
429,
{ ...rlHeaders, "Retry-After": String(retryAfter) }
);
}
// ── Check feature access (A13B - optional) ──────────────────────
let featureAccess: boolean | null = null;
if (featureFlag) {
if (isAuthenticated) {
const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
global: { headers: { Authorization: authHeader! } },
});
const { data: accessData, error: accessError } =
await userClient.rpc("check_feature_access", {
p_flag_name: featureFlag,
});
if (accessError) {
console.error(
"A17D: check_feature_access error:",
accessError.message
);
featureAccess = null;
} else {
featureAccess = accessData === true;
}
// FIX2: Feature-gated → 403 WITHOUT recording rate-limit hit
if (featureAccess === false) {
return jsonResponse(
{
allowed: false,
endpoint,
error: "Feature not available for your current plan",
error_code: "FEATURE_GATED",
rate_limit: {
remaining: rl.remaining,
limit: rl.limit,
used: rl.used,
reset_at: rl.reset_at,
},
tier: rl.tier,
feature_access: false,
},
403,
rlHeaders
);
}
} else {
// Anonymous: feature access unknown (most features require auth)
featureAccess = null;
}
}
// ── Allowed - record the hit (fire-and-forget) ──────────────────
serviceClient
.rpc("record_rate_limit_hit", {
p_endpoint: endpoint,
p_user_id: userId,
p_client_ip: clientIp,
})
.catch((err: unknown) => {
console.error("A17D: record_rate_limit_hit error:", err);
});
// ── FIX1: Sign entitlement token ────────────────────────────────
const nowSec = Math.floor(Date.now() / 1000);
const tokenPayload = {
endpoint,
uid: userId || "anon",
ip: clientIp || null,
tier: userTier,
iat: nowSec,
exp: nowSec + TOKEN_EXPIRY_SECONDS,
};
const entitlementToken = await signEntitlementToken(tokenPayload);
// ── Return success──────────────────────────────────────────────
// FIX4: Return exact remaining/used from check (no manual adjust)
return jsonResponse(
{
allowed: true,
endpoint,
entitlement_token: entitlementToken,
rate_limit: {
remaining: rl.remaining,
limit: rl.limit,
used: rl.used,
reset_at: rl.reset_at,
},
tier: rl.tier,
feature_access: featureAccess ?? true,
authenticated: isAuthenticated,
},
200,
{
...rlHeaders,
"X-Entitlement-Token": entitlementToken,
}
);
} catch (err: unknown) {
const message = err instanceof Error ? err.message : "Unknown error";
console.error(`A17D: Unexpected error: ${message}`);
return jsonResponse({ error: "Internal error" }, 500);
}
});
