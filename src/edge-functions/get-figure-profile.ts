// ========================================================================
// SUPABASE EDGE FUNCTION: get-figure-profile (V1.0.0)
// Path: supabase/functions/get-figure-profile/index.ts
//
// Aggregated profile analytics for a single figure:
//   - framing_distribution: 5-axis proportions from consensus records
//   - avg_signal_pulse: mean signal_rank across all ranked statements
//   - top_topic: most frequent topic across all statements
//   - last_statement_at: timestamp of most recent statement
//   - statement_count: total non-revoked statements
//
// AUTH: Anon (no JWT required). Public aggregate data.
// COST: $0.00: pure SQL aggregation, no AI calls.
// ========================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// ── ENV ────────────────────────────────────────────────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_KEY =
  String(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Valid framing labels (must match A1 enum + compute-consensus)
const VALID_FRAMING_LABELS = [
  "Adversarial / Oppositional",
  "Problem Identification",
  "Commitment / Forward-Looking",
  "Justification / Reactive",
  "Imperative / Directive",
];

// ── Service client ─────────────────────────────────────────────────────────
const serviceClient =
  SUPABASE_URL && SUPABASE_SERVICE_KEY
    ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
        auth: { persistSession: false },
      })
    : null;

// ── Helpers ────────────────────────────────────────────────────────────────

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

// ── Serve ──────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return withCors(new Response(null, { status: 204 }));
  }

  if (req.method !== "POST") {
    return withCors(json(405, { error: "Method not allowed" }));
  }

  // ── Env validation ────────────────────────────────────────────────────
  if (!serviceClient) {
    console.error("[get-figure-profile] Missing SUPABASE env vars");
    return withCors(json(500, { error: "Internal configuration error" }));
  }

  // ── Killswitch ────────────────────────────────────────────────────────
  const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
  if (ksRaw === "TRUE" || ksRaw.toLowerCase() === "true") {
    return withCors(
      json(503, { error: "Service temporarily unavailable" })
    );
  }

  const startTime = performance.now();

  try {
    // ── Parse body ────────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return withCors(json(400, { error: "Invalid JSON body" }));
    }

    const figureId = String(body.figure_id || "").trim();
    if (!UUID_REGEX.test(figureId)) {
      return withCors(
        json(400, { error: "figure_id must be a valid UUID" })
      );
    }

    // ── Guard: figure must be active + published ──────────────────
    const { data: figRow } = await serviceClient
      .from("figures")
      .select("figure_id, is_active, is_published")
      .eq("figure_id", figureId)
      .single();

    if (!figRow || !figRow.is_active || !figRow.is_published) {
      return withCors(json(404, { error: "Figure not found" }));
    }

    // ── Query: Statement aggregates via v_feed_ranked ──────────────
    // v_feed_ranked joins consensus for signal_rank + framing_consensus.
    // Already filters is_revoked=false and is_active=true.
    const { data: stmtRows, error: stmtErr } = await serviceClient
      .from("v_feed_ranked")
      .select(
        "statement_id, stated_at, topics, signal_rank, framing_consensus"
      )
      .eq("figure_id", figureId)
      .order("stated_at", { ascending: false });

    if (stmtErr) {
      console.error("[get-figure-profile] Statement query error", {
        message: stmtErr.message,
      });
      return withCors(json(500, { error: "Internal error" }));
    }

    const statements = stmtRows || [];
    const statementCount = statements.length;

    // ── Compute: last_statement_at ──────────────────────────────────
    const lastStatementAt =
      statements.length > 0 ? statements[0].stated_at : null;

    // ── Compute: avg_signal_pulse ───────────────────────────────────
    let avgSignalPulse: number | null = null;
    {
      let sum = 0;
      let count = 0;
      for (const s of statements) {
        const rank = Number(s.signal_rank);
        if (Number.isFinite(rank)) {
          sum += rank;
          count++;
        }
      }
      if (count > 0) {
        avgSignalPulse = Math.round((sum / count) * 1000) / 1000;
      }
    }

    // ── Compute: top_topic ──────────────────────────────────────────
    let topTopic: string | null = null;
    {
      const topicFreq: Record<string, number> = {};
      for (const s of statements) {
        const topics = s.topics;
        if (Array.isArray(topics)) {
          for (const t of topics) {
            if (typeof t === "string" && t.length > 0) {
              topicFreq[t] = (topicFreq[t] || 0) + 1;
            }
          }
        }
      }
      let maxCount = 0;
      for (const [topic, count] of Object.entries(topicFreq)) {
        if (count > maxCount) {
          maxCount = count;
          topTopic = topic;
        }
      }
    }

    // ── Compute: framing_distribution ───────────────────────────────
    // Count each framing label, normalize to 0.0–1.0
    const framingCounts: Record<string, number> = {};
    let framingTotal = 0;

    // Use framing_consensus from statements (v_statements_public)
    for (const s of statements) {
      const framing = String(s.framing_consensus || "").trim();
      if (framing && VALID_FRAMING_LABELS.includes(framing)) {
        framingCounts[framing] = (framingCounts[framing] || 0) + 1;
        framingTotal++;
      }
    }

    let framingDistribution: Record<string, number> | null = null;
    if (framingTotal > 0) {
      framingDistribution = {};
      for (const label of VALID_FRAMING_LABELS) {
        framingDistribution[label] =
          Math.round(((framingCounts[label] || 0) / framingTotal) * 1000) /
          1000;
      }
    }

    // ── Build response ──────────────────────────────────────────────
    const elapsedMs = Math.round(performance.now() - startTime);

    return withCors(
      json(200, {
        figure_id: figureId,
        statement_count: statementCount,
        last_statement_at: lastStatementAt,
        avg_signal_pulse: avgSignalPulse,
        top_topic: topTopic,
        framing_distribution: framingDistribution,
        meta: {
          elapsed_ms: elapsedMs,
          framing_sample_size: framingTotal,
        },
      }),
      120 // 2-min cache
    );
  } catch (err) {
    const elapsedMs = Math.round(performance.now() - startTime);
    console.error("[get-figure-profile] Unhandled error", {
      message: (err as Error)?.message,
      elapsed_ms: elapsedMs,
    });
    return withCors(json(500, { error: "Internal error" }));
  }
});
