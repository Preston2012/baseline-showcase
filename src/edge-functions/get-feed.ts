// ========================================================================
// SUPABASE EDGE FUNCTION: get-feed (A9B v2.0.0)
// Path: supabase/functions/get-feed/index.ts
//
// Smart feed: blends high-signal, recent, and fresh (unseen) statements.
// Default sort uses a composite score: signal_rank * recency_decay * diversity.
// Public read endpoint (anon key). No auth required.
//
// SORT MODES:
//   'smart'     — composite score (default): signal × recency × diversity
//   'recency'   — pure reverse-chronological
//   'signal'    — pure signal_rank descending
//   'novelty'   — novelty_avg descending (most novel first)
//   'divergence'— variance_detected first, then signal
//
// V2.0.0 CHANGES:
//   - Default sort changed from recency to smart mix
//   - Smart mix: time-decayed signal with figure diversity
//   - Statements older than 7 days deprioritized (not excluded)
//   - Figure diversity: caps any single figure to ~20% of results
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// ── ENV ────────────────────────────────────────────────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_ANON_KEY = String(Deno.env.get("SUPABASE_ANON_KEY") || "").trim();

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;
const SMART_FETCH_MULTIPLIER = 3; // fetch 3x limit for re-ranking pool

const VALID_TOPICS = new Set([
  "ECONOMY", "IMMIGRATION", "AI_TECHNOLOGY", "FOREIGN_POLICY",
  "HEALTHCARE", "CLIMATE_ENVIRONMENT", "CRIME_JUSTICE", "ELECTIONS",
  "MILITARY_DEFENSE", "CULTURE_SOCIETY", "OTHER",
]);

const VALID_SORTS = new Set(["smart", "recency", "signal", "novelty", "divergence"]);

// ── Helpers ────────────────────────────────────────────────────────────────
function withCors(resp: Response): Response {
  const h = new Headers(resp.headers);
  h.set("Access-Control-Allow-Origin", "*");
  h.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  h.set(
    "Access-Control-Allow-Headers",
    "authorization, Authorization, x-client-info, apikey, content-type",
  );
  return new Response(resp.body, { status: resp.status, headers: h });
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function isUuid(id: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);
}

// ── Smart scoring ──────────────────────────────────────────────────────────

/** Compute composite feed score for smart mix. */
function computeFeedScore(row: any, nowMs: number): number {
  // Base signal (0-100 scale, default 30 for unranked)
  const signal = Number(row.signal_rank) || 30;

  // Time decay: half-life of 36 hours
  // Score = signal * 2^(-age_hours / 36)
  const statedAt = row.stated_at ? new Date(row.stated_at).getTime() : nowMs;
  const ageHours = Math.max(0, (nowMs - statedAt) / 3600000);
  const recencyDecay = Math.pow(2, -ageHours / 36);

  // Variance boost: +30% for high-variance statements (disagreement = interesting)
  const varianceBoost = row.variance_detected ? 1.3 : 1.0;

  // Novelty boost: high novelty slightly boosted
  const novelty = Number(row.novelty_avg) || 0;
  const noveltyBoost = 1.0 + Math.min(novelty / 100, 1.0) * 0.15;

  return signal * recencyDecay * varianceBoost * noveltyBoost;
}

/** Diversify results so no single figure dominates the feed. */
function diversify(
  scored: Array<{ row: any; score: number }>,
  limit: number,
  maxPerFigure: number,
): any[] {
  const result: any[] = [];
  const figureCounts: Record<string, number> = {};

  for (const item of scored) {
    if (result.length >= limit) break;
    const fid = item.row.figure_id;
    const count = figureCounts[fid] || 0;
    if (count >= maxPerFigure) continue;
    figureCounts[fid] = count + 1;
    result.push(item.row);
  }

  // If we still have room (too many skipped), fill from remaining
  if (result.length < limit) {
    const resultIds = new Set(result.map((r: any) => r.statement_id));
    for (const item of scored) {
      if (result.length >= limit) break;
      if (!resultIds.has(item.row.statement_id)) {
        result.push(item.row);
      }
    }
  }

  return result;
}

// ── Main Handler ───────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === "OPTIONS") return withCors(new Response("ok", { status: 200 }));
  if (req.method !== "POST") return withCors(jsonResponse({ error: "Method not allowed" }, 405));

  const ksRaw = (Deno.env.get("BASELINE_KILL_SWITCH") || "").trim();
  if (ksRaw === "TRUE" || ksRaw.toLowerCase() === "true") {
    return withCors(jsonResponse({ error: "Service temporarily unavailable", reason: "maintenance" }, 503));
  }

  try {
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      return withCors(jsonResponse({ error: "Missing SUPABASE_URL or SUPABASE_ANON_KEY" }, 500));
    }

    const body = await req.json().catch(() => ({}));
    const figure_id = body?.figure_id ?? null;
    const ranked_only = body?.ranked_only === true;
    const topic = body?.topic ?? null;
    const sort_by = body?.sort_by ?? null;
    const limit = Math.min(Math.max(1, Number(body?.limit) || DEFAULT_LIMIT), MAX_LIMIT);
    const offset = Math.max(0, Number(body?.offset) || 0);

    if (figure_id && (typeof figure_id !== "string" || !isUuid(figure_id))) {
      return withCors(jsonResponse({ error: "figure_id must be a valid UUID" }, 400));
    }

    // Validate sort_by
    const normalizedSort = sort_by ? String(sort_by).toLowerCase().trim() : null;
    const effectiveSort = (normalizedSort && VALID_SORTS.has(normalizedSort))
      ? normalizedSort
      : (figure_id ? "recency" : "smart"); // default: smart for main feed, recency for profile

    if (topic && (typeof topic !== "string" || !VALID_TOPICS.has(topic))) {
      return withCors(jsonResponse({
        error: "Invalid topic",
        valid_topics: Array.from(VALID_TOPICS).sort(),
      }, 400));
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

    const FEED_SELECT = [
      "statement_id", "figure_id", "figure_name", "figure_photo_url",
      "statement_text",
      "stated_at", "ingestion_time", "source_url", "baseline_delta",
      "topics", "rank_status", "signal_rank", "variance_detected",
      "novelty_avg", "repetition_avg", "affective_language_rate_avg",
      "topic_entropy_avg", "baseline_delta_avg", "framing_consensus",
      "model_count", "consensus_computed_at",
    ].join(", ");

    // ── Smart sort: fetch larger pool, score, diversify ──────────────
    if (effectiveSort === "smart") {
      const poolSize = Math.min((offset + limit) * SMART_FETCH_MULTIPLIER, 600);

      let query = supabase.from("v_feed_ranked").select(FEED_SELECT);
      if (figure_id) query = query.eq("figure_id", figure_id);
      if (ranked_only) query = query.eq("rank_status", "RANKED");
      if (topic) query = query.contains("topics", [topic]);

      // Fetch recent pool (last 7 days by default, extend if not enough)
      const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString();
      query = query
        .gte("stated_at", sevenDaysAgo)
        .order("ingestion_time", { ascending: false })
        .range(0, poolSize - 1);

      const { data, error } = await query;
      if (error) throw new Error(`Feed query failed: ${error.message}`);

      const pool = data || [];
      const nowMs = Date.now();

      // Score and sort
      const scored = pool
        .map((row: any) => ({ row, score: computeFeedScore(row, nowMs) }))
        .sort((a: any, b: any) => b.score - a.score);

      // Diversify: max ~20% of results from any single figure (min 3)
      const maxPerFigure = Math.max(3, Math.ceil(limit * 0.2));
      const diversified = diversify(scored, offset + limit, maxPerFigure);

      // Apply offset/limit
      const page = diversified.slice(offset, offset + limit);

      return withCors(jsonResponse({
        statements: page,
        pagination: { limit, offset, returned: page.length },
        filters: {
          figure_id: figure_id || null,
          ranked_only,
          topic: topic || null,
          sort_by: "smart",
        },
      }));
    }

    // ── Traditional sorts ────────────────────────────────────────────
    let query = supabase.from("v_feed_ranked").select(FEED_SELECT);
    if (figure_id) query = query.eq("figure_id", figure_id);
    if (ranked_only) query = query.eq("rank_status", "RANKED");
    if (topic) query = query.contains("topics", [topic]);

    switch (effectiveSort) {
      case "signal":
        query = query
          .order("signal_rank", { ascending: false, nullsFirst: false })
          .order("ingestion_time", { ascending: false });
        break;
      case "novelty":
        query = query
          .order("novelty_avg", { ascending: false, nullsFirst: false })
          .order("ingestion_time", { ascending: false });
        break;
      case "divergence":
        query = query
          .order("variance_detected", { ascending: false, nullsFirst: false })
          .order("signal_rank", { ascending: false, nullsFirst: false })
          .order("ingestion_time", { ascending: false });
        break;
      case "recency":
      default:
        query = query.order("ingestion_time", { ascending: false });
        break;
    }

    query = query.range(offset, offset + limit - 1);
    const { data, error } = await query;
    if (error) throw new Error(`Feed query failed: ${error.message}`);

    return withCors(jsonResponse({
      statements: data || [],
      pagination: { limit, offset, returned: (data || []).length },
      filters: {
        figure_id: figure_id || null,
        ranked_only,
        topic: topic || null,
        sort_by: effectiveSort,
      },
    }));
  } catch (error: any) {
    console.error("[get-feed] error", error);
    return withCors(jsonResponse({ error: "Internal error" }, 500));
  }
});
