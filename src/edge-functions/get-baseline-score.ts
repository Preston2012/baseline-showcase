// ========================================================================
// SUPABASE EDGE FUNCTION: get-baseline-score (V1.2.0)
// Deploy to: supabase/functions/get-baseline-score/index.ts
//
// Baseline™ brand metric. Rolling 24h AVG(signal_rank) per figure.
// Wraps the get_baseline_score SQL function with CORS, validation,
// killswitch, and error handling.
//
// CROSS-ARTIFACT DEPENDENCIES:
// A1 V8.0: statements, consensus tables
// A9B: Pattern reference (anon POST, CORS, killswitch)
//
// AUTH: Anon (no JWT required). Public aggregate data.
// COST: $0.00: pure SQL, no AI calls.
// ========================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// ── ENV (read at module level, validated per-request) ────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_KEY =
  String(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();

// ── Constants ────────────────────────────────────────────────────────────────
const MIN_FIGURES = 1;
const MAX_FIGURES = 50;
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ── Service client (module-level, reused across requests) ────────────────────
// No per-user state. Anon endpoint, service_role for RPC access.
// Auth subsystem disabled to avoid unnecessary GoTrue/Realtime allocation.
const serviceClient = SUPABASE_URL && SUPABASE_SERVICE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    })
  : null;

// ── Helpers ──────────────────────────────────────────────────────────────────

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function withCors(response: Response, maxAge?: number): Response {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) {
    headers.set(k, v);
  }
  if (maxAge !== undefined) {
    headers.set("Cache-Control", `public, max-age=${maxAge}`);
  }
  return new Response(response.body, {
    status: response.status,
    headers,
  });
}

// ── Startup log (once) ──────────────────────────────────────────────────────
let _started = false;

// ── Serve ───────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return withCors(new Response(null, { status: 204 }));
  }

  const startTime = performance.now();

  // Startup log (first request only)
  if (!_started) {
    console.log("[get-baseline-score] Cold start", {
      url_set: !!SUPABASE_URL,
      key_set: !!SUPABASE_SERVICE_KEY,
    });
    _started = true;
  }

  // ── Method check ────────────────────────────────────────────────────────
  if (req.method !== "POST") {
    return withCors(json(405, { error: "Method not allowed" }));
  }

  // ── Env validation (check module-level client) ───────────────────────────
  if (!serviceClient) {
    console.error("[get-baseline-score] Missing SUPABASE env vars");
    return withCors(json(500, { error: "Internal configuration error" }));
  }

  // ── Killswitch ──────────────────────────────────────────────────────────
  const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
  const killswitchActive = ksRaw === "TRUE" || ksRaw.toLowerCase() === "true";
  if (killswitchActive) {
    console.log("[get-baseline-score] BASELINE_KILL_SWITCH active");
    return withCors(json(503, { error: "Service temporarily unavailable" }));
  }

  try {
    // ── Parse body ──────────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return withCors(json(400, { error: "Invalid JSON body" }));
    }

    // ── Validate figure_ids ─────────────────────────────────────────────
    const rawIds = body.figure_ids;
    if (!Array.isArray(rawIds)) {
      return withCors(
        json(400, { error: "figure_ids must be a non-empty array of UUIDs" })
      );
    }

    // Deduplicate
    const uniqueIds = [...new Set(rawIds.map((id) => String(id).trim()))];

    // Validate count
    if (uniqueIds.length < MIN_FIGURES || uniqueIds.length > MAX_FIGURES) {
      return withCors(
        json(400, {
          error: `figure_ids must contain ${MIN_FIGURES}-${MAX_FIGURES} UUIDs (got ${uniqueIds.length})`,
        })
      );
    }

    // Validate UUID format
    for (const id of uniqueIds) {
      if (!UUID_REGEX.test(id)) {
        return withCors(
          json(400, { error: `Invalid UUID: ${Array.from(id).slice(0, 40).join('')}` })
        );
      }
    }

    // ── Call SQL function ───────────────────────────────────────────────
    const { data, error } = await serviceClient.rpc("get_baseline_score", {
      p_figure_ids: uniqueIds,
    });

    if (error) {
      console.error("[get-baseline-score] RPC error", {
        message: error.message,
        code: error.code,
      });
      return withCors(json(500, { error: "Internal error" }));
    }

    // ── Build response ──────────────────────────────────────────────────
    // data is an array of { figure_id, baseline_score, statement_count }
    // Figures with no 24h data are simply absent from results.
    const scores = (data || []).map(
      (row: {
        figure_id: string;
        baseline_score: number | null;
        statement_count: number;
      }) => ({
        figure_id: row.figure_id,
        baseline_score: row.baseline_score === null ? null : Number(row.baseline_score),
        statement_count: row.statement_count,
      })
    );

    const elapsedMs = Math.round(performance.now() - startTime);

    const response = {
      scores,
      meta: {
        requested: uniqueIds.length,
        returned: scores.length,
        window_hours: 24,
        elapsed_ms: elapsedMs,
      },
    };

    return withCors(json(200, response), 60); // 60s public cache
  } catch (err) {
    const elapsedMs = Math.round(performance.now() - startTime);
    console.error("[get-baseline-score] Unhandled error", {
      message: (err as Error)?.message,
      elapsed_ms: elapsedMs,
    });
    return withCors(json(500, { error: "Internal error" }));
  }
});
