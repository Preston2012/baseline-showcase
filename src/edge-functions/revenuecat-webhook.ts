// ========================================================================
// BASELINE V1.4 — REVENUECAT WEBHOOK ENDPOINT
// A17B — V1.0.1
//
// FIXES APPLIED (V1.0.0 → V1.0.1 — dual audit reconciliation):
// FIX1: Idempotency / replay protection. Extracts rc_event_id from
// payload (event.id) and checks subscription_events before
// processing. Duplicates return 200 + already_processed. Prevents
// junk rows + redundant tier syncs on RC retries.
// [Audit 2 Critical Blocker #1]
// FIX2: auto_renew_enabled now reads explicit RC fields if present
// (is_auto_renewing / auto_renew_status). Falls back to null
// (DB preserves last known) instead of guessing from event type.
// [Audit 2 Critical Blocker #2]
// FIX3: Removed CORS entirely. Server-to-server webhook has no browser
// caller. No OPTIONS handler, no Access-Control-Allow-* headers.
// [Audit 1 Security + Audit 2 Critical Blocker #3]
// FIX4: Constant-time auth comparison via HMAC-based timing-safe check.
// Prevents timing side-channel on Bearer secret.
// [Audit 2 High #4]
// FIX5: Event type normalized to UPPERCASE before mapping. Prevents
// dropping valid events if RC sends mixed casing.
// [Audit 2 High #5]
// FIX6: PII sanitization switched from blocklist to allowlist. Only
// explicitly safe fields are persisted in raw_event JSONB.
// [Audit 2 High #6]
// FIX7: Supabase client hardened — autoRefreshToken and persistSession
// disabled. Service-role client doesn't need session management.
// [Audit 2 Medium #7]
// FIX8: Store mapping defaults to 'promotional' (not 'app_store') for
// unknown stores. DB CHECK constraint catches truly invalid values.
// [Audit 2 Medium #8]
// FIX9: Console log messages sanitized — no user_id or PII in error logs.
// [Audit 1 Security note]
//
// PURPOSE:
// Receives RevenueCat server-to-server webhook events, maps them to
// Baseline subscription lifecycle, and calls A17A's upsert_subscription()
// RPC to persist state + sync user tier.
//
// DEPENDENCIES:
// - A17A V1.0.1 deployed (subscriptions, subscription_events,
// upsert_subscription(), map_product_to_tier())
// - A13A V1.0.2 deployed (user_profiles, protect_user_tier)
// - A13B V1.0.1 deployed (tier_features — A13B owns, not A17A)
// - Supabase Edge Functions runtime (Deno)
//
// WHAT THIS DOES NOT DO:
// - Does not manage tier_features (A13B owns that)
// - Does not enforce rate limits (A17C/D handles that)
// - Does not handle Apple/Google server verification (RevenueCat does that)
// - Does not process refund chargebacks (RevenueCat handles disputes)
// - Does not run expire_lapsed cron (separate cron calls A17A RPC)
//
// ENDPOINT:
// POST /revenuecat-webhook
// Body: RevenueCat webhook payload (v4 API)
// Auth: Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>
// No CORS — server-to-server only.
//
// REVENUECAT EVENT → BASELINE EVENT MAPPING:
// INITIAL_PURCHASE → INITIAL_PURCHASE
// RENEWAL → RENEWAL
// CANCELLATION → CANCELLATION
// UNCANCELLATION → UNCANCELLATION
// BILLING_ISSUE → BILLING_ISSUE_DETECTED
// PRODUCT_CHANGE → PRODUCT_CHANGE
// EXPIRATION → EXPIRATION
// TRANSFER → TRANSFER
// SUBSCRIBER_ALIAS → (ignored — alias management)
// TEST → (ignored — test ping)
//
// IDEMPOTENCY:
// RevenueCat retries on 5xx and may send duplicates. We extract
// event.id as rc_event_id, embed it in raw_event JSONB, and query
// subscription_events for existing matches before processing.
// Duplicates get 200 + already_processed (no DB write, no tier sync).
//
// SECURITY:
// - Constant-time Bearer token auth (REVENUECAT_WEBHOOK_SECRET)
// - Service-role Supabase client (calls SECURITY DEFINER RPCs)
// - No user JWT involved (server-to-server)
// - KILLSWITCH respected
// - No CORS headers (not browser-accessible)
// - PII allowlist sanitization on raw_event
//
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// ── ENV (read at module level, validated per-request) ────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_ROLE_KEY = String(
Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
).trim();
const REVENUECAT_WEBHOOK_SECRET = String(
Deno.env.get("REVENUECAT_WEBHOOK_SECRET") || ""
).trim();
// ── Constants────────────────────────────────────────────────────────────
// RevenueCat event type → Baseline event_type mapping
// Keys are UPPERCASE (FIX5: input normalized before lookup)
const EVENT_TYPE_MAP: Record<string, string> = {
INITIAL_PURCHASE: "INITIAL_PURCHASE",
RENEWAL: "RENEWAL",
CANCELLATION: "CANCELLATION",
UNCANCELLATION: "UNCANCELLATION",
BILLING_ISSUE: "BILLING_ISSUE_DETECTED",
PRODUCT_CHANGE: "PRODUCT_CHANGE",
EXPIRATION: "EXPIRATION",
TRANSFER: "TRANSFER",
};
// Events we intentionally skip (return 200 so RC doesn't retry)
const IGNORED_EVENTS = new Set(["SUBSCRIBER_ALIAS", "TEST"]);
// RevenueCat event type → Baseline subscription status
const STATUS_MAP: Record<string, string> = {
INITIAL_PURCHASE: "active",
RENEWAL: "active",
CANCELLATION: "cancelled",
UNCANCELLATION: "active",
BILLING_ISSUE: "billing_issue",
PRODUCT_CHANGE: "active",
EXPIRATION: "expired",
TRANSFER: "active",
};
// RevenueCat store → Baseline store
// FIX8: No default fallback here — handled explicitly below
const STORE_MAP: Record<string, string> = {
APP_STORE: "app_store",
PLAY_STORE: "play_store",
STRIPE: "stripe",
PROMOTIONAL: "promotional",
};
const UUID_REGEX =
/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// ── Helpers──────────────────────────────────────────────────────────────
function jsonResponse(
body: Record<string, unknown>,
status = 200
): Response {
return new Response(JSON.stringify(body), {
status,
headers: { "Content-Type": "application/json" },
});
}
function parseKillswitch(): boolean {
const v = String(Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
return v === "TRUE" || v.toLowerCase() === "true";
}
// ── FIX4: Constant-time string comparison ────────────────────────────────
// Uses HMAC(key=a, msg=a) vs HMAC(key=a, msg=b) with byte-level XOR.
// Avoids timing side-channels on secret length and content.
async function constantTimeEqual(a: string, b: string): Promise<boolean> {
const encoder = new TextEncoder();
const aBuf = encoder.encode(a);
const bBuf = encoder.encode(b);
// HMAC both with same key — output is always 32 bytes regardless of input
// This makes the comparison constant-time even if input lengths differ
const keyMaterial = await crypto.subtle.importKey(
"raw",
encoder.encode("baseline-webhook-compare"),
{ name: "HMAC", hash: "SHA-256" },
false,
["sign"]
);
const sigA = new Uint8Array(
await crypto.subtle.sign("HMAC", keyMaterial, aBuf)
);
const sigB = new Uint8Array(
await crypto.subtle.sign("HMAC", keyMaterial, bBuf)
);
// Fixed-length 32-byte comparison — always runs full loop
if (sigA.byteLength !== sigB.byteLength) return false;
let result = 0;
for (let i = 0; i < sigA.byteLength; i++) {
result |= sigA[i] ^ sigB[i];
}
return result === 0;
}
// Convert RevenueCat millisecond timestamps to ISO strings (or null)
function msToIso(ms: unknown): string | null {
if (ms === null || ms === undefined) return null;
const num = typeof ms === "number" ? ms : Number(ms);
if (!Number.isFinite(num) || num <= 0) return null;
return new Date(num).toISOString();
}
// Derive plan_type from product_id
function derivePlanType(productId: string): string {
const lower = productId.toLowerCase();
if (lower.includes("annual") || lower.includes("yearly")) return "annual";
if (lower.includes("lifetime")) return "lifetime";
if (lower.includes("promo") || lower.includes("admin")) return "promotional";
return "monthly";
}
// ── FIX2: Extract auto_renew from explicit RC fields, or null ────────────
// Prefers real fields over heuristic. null = "don't overwrite DB value".
function extractAutoRenew(event: Record<string, unknown>): boolean | null {
// Prefer explicit boolean fields (RC v4 API)
if (typeof event.is_auto_renewing === "boolean") {
return event.is_auto_renewing;
}
if (typeof event.auto_renew_status === "boolean") {
return event.auto_renew_status;
}
// Handle string variants ("true"/"false")
if (typeof event.is_auto_renewing === "string") {
const v = event.is_auto_renewing.toLowerCase();
if (v === "true") return true;
if (v === "false") return false;
}
if (typeof event.auto_renew_status === "string") {
const v = event.auto_renew_status.toLowerCase();
if (v === "true") return true;
if (v === "false") return false;
}
// Unknown: return null to preserve last known value in DB
return null;
}
// ── FIX6: Allowlist-based raw event sanitization ─────────────────────────
// Only persist fields needed for debugging/analytics. Everything else dropped.
// No PII (email, phone, IP, subscriber_attributes) stored.
function sanitizeRawEvent(
event: Record<string, unknown>,
rcEventId: string | null
): Record<string, unknown> {
const ALLOWED_KEYS = new Set([
"type",
"id",
"product_id",
"store",
"environment",
"purchased_at_ms",
"expiration_at_ms",
"event_timestamp_ms",
"original_purchased_at_ms",
"entitlement_ids",
"period_type",
"presented_offering_id",
"currency",
"price",
"price_in_purchased_currency",
"takehome_percentage",
"country_code",
"is_trial_conversion",
"is_family_share",
"is_auto_renewing",
"auto_renew_status",
"cancellation_reason",
"grace_period_expires_date_ms",
"auto_resume_date_ms",
]);
const sanitized: Record<string, unknown> = {};
for (const key of ALLOWED_KEYS) {
if (key in event && event[key] !== undefined) {
sanitized[key] = event[key];
}
}
// Always embed dedupe key for idempotency queries
if (rcEventId) {
sanitized.rc_event_id = rcEventId;
}
return sanitized;
}
// ── Main Handler─────────────────────────────────────────────────────────
serve(async (req: Request) => {
// FIX3: No OPTIONS/CORS — server-to-server only. POST required.
if (req.method !== "POST") {
return jsonResponse({ error: "Method not allowed" }, 405);
}
// KILLSWITCH
if (parseKillswitch()) {
console.log("[revenuecat-webhook] BASELINE_KILL_SWITCH active — rejecting");
return jsonResponse(
{ error: "Service halted", reason: "BASELINE_KILL_SWITCH active" },
503
);
}
// Env validation
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
console.error("A17B: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
return jsonResponse({ error: "Server configuration error" }, 500);
}
if (!REVENUECAT_WEBHOOK_SECRET) {
console.error("A17B: Missing REVENUECAT_WEBHOOK_SECRET");
return jsonResponse({ error: "Server configuration error" }, 500);
}
// ── FIX4: Constant-time Bearer auth ───────────────────────────────────
const authHeader =
req.headers.get("Authorization") || req.headers.get("authorization");
if (!authHeader) {
return jsonResponse({ error: "Unauthorized" }, 401);
}
const expectedToken = `Bearer ${REVENUECAT_WEBHOOK_SECRET}`;
const authValid = await constantTimeEqual(authHeader, expectedToken);
if (!authValid) {
return jsonResponse({ error: "Unauthorized" }, 401);
}
// ── Parse body────────────────────────────────────────────────────────
let body: Record<string, unknown>;
try {
body = await req.json();
} catch {
return jsonResponse({ error: "Invalid JSON body" }, 400);
}
// RevenueCat sends { event: { ... } } or { api_version, event: { ... } }
const event = body.event as Record<string, unknown> | undefined;
if (!event || typeof event !== "object") {
return jsonResponse({ error: "Missing or invalid event object" }, 400);
}
// ── FIX5: Normalize event type to UPPERCASE ───────────────────────────
const rcEventType = String(event.type || "").trim().toUpperCase();
// Ignored events (return 200 so RC doesn't retry)
if (IGNORED_EVENTS.has(rcEventType)) {
console.log(`A17B: Ignoring event type: ${rcEventType}`);
return jsonResponse({ received: true, ignored: true, event_type: rcEventType });
}
// Map event type
const baselineEventType = EVENT_TYPE_MAP[rcEventType];
if (!baselineEventType) {
console.warn(`A17B: Unknown RevenueCat event type: ${rcEventType}`);
return jsonResponse({
received: true,
ignored: true,
reason: "unknown_event_type",
event_type: rcEventType,
});
}
// ── FIX1: Extract RC event ID for idempotency ────────────────────────
const rcEventId = String(event.id || event.event_id || "").trim() || null;
// ── Extract fields from RevenueCat payload ────────────────────────────
const appUserId = String(event.app_user_id || "").trim();
const originalAppUserId = String(event.original_app_user_id || "").trim();
const productId = String(event.product_id || "").trim();
const rcStore = String(event.store || "").trim().toUpperCase();
const rcEnvironment = String(event.environment || "PRODUCTION")
.trim()
.toUpperCase();
// Entitlement IDs (RC sends array)
const entitlementIds = Array.isArray(event.entitlement_ids)
? event.entitlement_ids
: [];
const entitlementId =
entitlementIds.length > 0 ? String(entitlementIds[0]) : null;
// Timestamps (RC sends milliseconds)
const periodStart = msToIso(event.purchased_at_ms);
const periodEnd = msToIso(event.expiration_at_ms);
const originalPurchaseDate = msToIso(
event.original_purchased_at_ms ?? event.purchased_at_ms
);
const cancellationDate = msToIso(event.cancellation_date_ms);
const unsubscribeDetectedAt = msToIso(event.unsubscribe_detected_at_ms);
const gracePeriodExpiresAt = msToIso(event.grace_period_expires_date_ms);
// FIX2: Auto-renew from explicit RC field or null (preserves DB value)
const autoRenewEnabled = extractAutoRenew(event);
// ── Validate required fields──────────────────────────────────────────
if (!appUserId) {
console.error("A17B: Missing app_user_id in event");
return jsonResponse({ error: "Missing app_user_id" }, 400);
}
if (!productId) {
console.error("A17B: Missing product_id in event");
return jsonResponse({ error: "Missing product_id" }, 400);
}
// ── Resolve Supabase user_id from app_user_id ─────────────────────────
// RevenueCat app_user_id should be set to Supabase auth.users.id during
// SDK initialization. Fallback to original_app_user_id for transfers.
let userId: string;
if (UUID_REGEX.test(appUserId)) {
userId = appUserId;
} else if (UUID_REGEX.test(originalAppUserId)) {
userId = originalAppUserId;
console.warn("A17B: app_user_id not UUID, falling back to original");
} else {
// FIX9: No PII in logs
console.error("A17B: Cannot resolve user_id from event — neither field is UUID");
return jsonResponse({
received: true,
skipped: true,
reason: "unresolvable_user_id",
});
}
// ── FIX8: Map store (default 'promotional' for unknown, not 'app_store')
const mappedStore = STORE_MAP[rcStore];
if (!mappedStore) {
console.warn(`A17B: Unknown store value, defaulting to promotional`);
}
const store = mappedStore || "promotional";
const environment = rcEnvironment === "SANDBOX" ? "sandbox" : "production";
// Derive plan type + status
const planType = derivePlanType(productId);
const status = STATUS_MAP[rcEventType] || "active";
// ── FIX7: Supabase client hardened (no session persistence) ───────────
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
auth: { autoRefreshToken: false, persistSession: false },
});
try {
// ── FIX1: Idempotency check — skip if rc_event_id already processed ─
// Queries raw_event JSONB for the dedupe key. If found, short-circuit.
// This prevents duplicate subscription_events rows and redundant tier syncs.
if (rcEventId) {
const { data: existing, error: dedupeErr } = await supabase
.from("subscription_events")
.select("event_id")
.eq("raw_event->>rc_event_id", rcEventId)
.limit(1);
if (!dedupeErr && existing && existing.length > 0) {
console.log(`A17B: Duplicate rc_event_id detected — skipping`);
return jsonResponse({
received: true,
already_processed: true,
rc_event_id: rcEventId,
});
}
// If dedupeErr: log but proceed (fail-open on dedupe, fail-closed would
// drop events on transient DB issues — worse outcome)
if (dedupeErr) {
console.warn("A17B: Dedupe check failed, proceeding:", dedupeErr.message);
}
}
// ── Call upsert_subscription RPC ────────────────────────────────────
const { data, error } = await supabase.rpc("upsert_subscription", {
p_user_id: userId,
p_event_type: baselineEventType,
p_product_id: productId,
p_plan_type: planType,
p_status: status,
p_store: store,
p_environment: environment,
p_current_period_start: periodStart,
p_current_period_end: periodEnd,
p_original_purchase_date: originalPurchaseDate,
p_revenuecat_app_user_id: appUserId,
p_revenuecat_original_id: originalAppUserId || null,
p_entitlement_id: entitlementId,
p_cancellation_date: cancellationDate,
p_unsubscribe_detected_at: unsubscribeDetectedAt,
p_grace_period_expires_at: gracePeriodExpiresAt,
p_auto_renew_enabled: autoRenewEnabled,
p_raw_event: sanitizeRawEvent(event as Record<string, unknown>, rcEventId),
});
if (error) {
console.error("A17B: upsert_subscription RPC error:", error.message);
// User not in auth.users: return 200 to prevent infinite RC retries
if (
error.message.includes("violates foreign key") ||
error.message.includes("not found")
) {
console.warn("A17B: User not found in auth.users — skipping event");
return jsonResponse({
received: true,
skipped: true,
reason: "user_not_found",
});
}
// Genuine errors: 500 → RC retries with backoff
return jsonResponse(
{ error: "Failed to process subscription event" },
500
);
}
console.log(
`A17B: Processed ${rcEventType} → tier=${data?.tier} status=${status}`
);
return jsonResponse({
received: true,
processed: true,
event_type: baselineEventType,
subscription_id: data?.subscription_id,
tier: data?.tier,
status,
});
} catch (err: unknown) {
const message = err instanceof Error ? err.message : "Unknown error";
console.error(`A17B: Unexpected error: ${message}`);
return jsonResponse({ error: "Internal error" }, 500);
}
});
