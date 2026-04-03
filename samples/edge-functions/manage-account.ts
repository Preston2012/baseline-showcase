// ========================================================================
// SUPABASE EDGE FUNCTION: manage-account (A15B)
// Handles account deletion requests from authenticated users.
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
  const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
  if (killswitchActive) {
    return json({ error: "Service temporarily unavailable", reason: "maintenance" }, 503);
  }

  try {
    // Get the user's JWT from the Authorization header
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");

    if (!token) {
      return json({ error: "Not authenticated" }, 401);
    }

    // Create client with user's token to verify identity
    const userClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: { user }, error: userErr } = await userClient.auth.getUser(token);
    if (userErr || !user) {
      return json({ error: "Invalid session" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const action = body.action;

    if (action !== "delete_account") {
      return json({ error: "Unknown action" }, 400);
    }

    // Use service role client for admin operations
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Clean up user data (annotations, subscriptions)
    await adminClient.from("annotations").delete().eq("user_id", user.id);
    await adminClient.from("subscriptions").delete().eq("user_id", user.id);
    await adminClient.from("subscription_events").delete().eq("user_id", user.id);
    await adminClient.from("user_profiles").delete().eq("user_id", user.id);

    // Delete the auth user
    const { error: deleteErr } = await adminClient.auth.admin.deleteUser(user.id);
    if (deleteErr) {
      console.error("Failed to delete user:", deleteErr);
      return json({ error: "Failed to delete account", code: "DELETE_FAILED" }, 500);
    }

    console.log(`Account deleted: ${user.id}`);
    return json({ success: true });

  } catch (err) {
    console.error("manage-account error:", err);
    return json({ error: "Internal error" }, 500);
  }
});
