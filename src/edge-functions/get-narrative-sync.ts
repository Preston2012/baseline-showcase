// ========================================================================
// SUPABASE EDGE FUNCTION: get-narrative-sync (A-17E V1.2.0 LOCKED)
// Deploy to: supabase/functions/get-narrative-sync/index.ts
//
// Narrative Sync™: B2B-exclusive cross-figure framing convergence.
// Reads existing consensus + statements + figures tables.
// Zero AI compute. Pure SQL aggregation + TypeScript convergence detection.
//
// V1.0.1 CHANGES:
// 1: Pipeline events logging (A11A, best-effort, A7B/A12B pattern)
// 2: Request timing (elapsed_ms)
// 3: Deterministic framing tie-break (alphabetical)
// 4: Max date range (365 days)
// 5: Metric proximity detection (signal_rank within 5pts)
// 6: Cache-Control header (private, 5min)
// 7: Request ID for tracing
// 8: Clean empty response (0 statements ≠ error)
// 9: Parallel figure + statement fetch
// 10: Empty topic_filter to null normalization
//
// CROSS-ARTIFACT DEPENDENCIES:
// A1 V8.0: consensus, statements, figures tables
// A3: Framing labels (5 canonical values)
// A11A: pipeline_events table (best-effort logging)
// A13A: user_profiles table (tier check)
//
// PATTERN NOTES:
// - Follows A7B/A9B/A14B conventions (CORS, killswitch, env validation,
//   JSON helpers, pipeline event logging)
// - Service-role client for data reads (bypasses RLS for aggregation)
// - User JWT verified via supabase.auth.getUser() for tier check
// ========================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// ── ENV (read at module level, validated per-request) ────────────────────────
const SUPABASE_URL = String(Deno.env.get("SUPABASE_URL") || "").trim();
const SUPABASE_SERVICE_KEY =
  String(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();
const SUPABASE_ANON_KEY =
  String(Deno.env.get("SUPABASE_ANON_KEY") || "").trim();

// ── Module-level service client (no per-request state needed) ────────────────
// persistSession: false disables unnecessary GoTrue/Realtime subsystems.
const serviceClient = SUPABASE_URL && SUPABASE_SERVICE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    })
  : null;

// ── Constants ────────────────────────────────────────────────────────────────
const MAX_FIGURES = 10;
const MIN_FIGURES = 2;
const MAX_DATE_RANGE_DAYS = 365; // V1.0.1 FIX4: Cap runaway queries
const METRIC_PROXIMITY_THRESHOLD = 5.0; // V1.0.1 FIX5: signal_rank delta
const VALID_BUCKETS = new Set(["week", "month"]);
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

// ── Helpers ──────────────────────────────────────────────────────────────────
function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function withCors(response: Response, cacheSeconds = 0): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  headers.set(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, x-client-info, apikey"
  );
  // V1.0.1 FIX6: Cache-Control for B2B (private, short TTL)
  if (cacheSeconds > 0) {
    headers.set("Cache-Control", `private, max-age=${cacheSeconds}`);
  }
  return new Response(response.body, {
    status: response.status,
    headers,
  });
}

function parseKillswitch(): boolean {
  const v = String(Deno.env.get("BASELINE_KILL_SWITCH") || "FALSE").trim();
  return v === "TRUE" || v.toLowerCase() === "true";
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

function daysBetween(a: string, b: string): number {
  const ms = new Date(b).getTime() - new Date(a).getTime();
  return Math.ceil(ms / (1000 * 60 * 60 * 24));
}

// V1.0.1 FIX1: Pipeline event logging (matches A7B/A12B pattern)
// Stage = CONSENSUS (closest match: reading consensus data for convergence)
// Best-effort: failures never block main flow
async function logPipelineEvent(
  supabase: any,
  requestId: string,
  eventType: string,
  details: Record<string, any>
): Promise<void> {
  try {
    await supabase.from("pipeline_events").insert({
      statement_id: null,
      stage: "CONSENSUS",
      event_type: eventType,
      details: { workflow: "A17E", request_id: requestId, ...details },
    });
  } catch {
    // Best-effort: never block main flow
  }
}

// ── Startup log (once) ──────────────────────────────────────────────────────
let _started = false;

// ── Serve ───────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return withCors(new Response(null, { status: 204 }));
  }

  // V1.0.1 FIX7: Request ID for tracing
  const requestId = crypto.randomUUID();
  // V1.0.1 FIX2: Request timing
  const startTime = performance.now();

  // Startup log (first request only)
  if (!_started) {
    console.log("[get-narrative-sync] Cold start", {
      url_set: !!SUPABASE_URL,
      key_set: !!SUPABASE_SERVICE_KEY,
      anon_key_set: !!SUPABASE_ANON_KEY,
    });
    _started = true;
  }

  try {
    // ── ENV validation ────────────────────────────────────────────────────
    if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY || !SUPABASE_ANON_KEY) {
      console.error("[get-narrative-sync] Missing env vars", { requestId });
      return withCors(json(500, { error: "Server misconfigured" }));
    }

    // ── Killswitch (per-request, matches A7B pattern) ─────────────────────
    if (parseKillswitch()) {
      return withCors(
        json(503, { error: "Service temporarily unavailable" })
      );
    }

    // ── Method check ──────────────────────────────────────────────────────
    if (req.method !== "POST") {
      return withCors(json(405, { error: "Method not allowed" }));
    }

    // ── Auth: verify JWT ──────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return withCors(json(401, { error: "Authentication required" }));
    }

    const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await anonClient.auth.getUser();

    if (authError || !user) {
      return withCors(json(401, { error: "Authentication required" }));
    }

    // ── Tier check (defense-in-depth: B2B only) ─────────────────────────
    if (!serviceClient) {
      console.error("[get-narrative-sync] Service client not initialized", { requestId });
      return withCors(json(500, { error: "Server misconfigured" }));
    }

    // Direct user_profiles lookup (service-role bypasses RLS)
    const { data: profileData, error: profileError } = await serviceClient
      .from("user_profiles")
      .select("tier")
      .eq("user_id", user.id)
      .single();

    if (profileError || !profileData) {
      console.error("[get-narrative-sync] Tier lookup failed", {
        requestId,
        user_id: user.id,
        error: profileError?.message,
      });
      return withCors(json(403, { error: "B2B tier required" }));
    }

    const userTier = profileData.tier || "free";
    if (userTier !== "b2b") {
      return withCors(json(403, { error: "B2B tier required" }));
    }

    // ── Parse + validate body ─────────────────────────────────────────────
    let body: {
      figure_ids?: string[];
      start_date?: string;
      end_date?: string;
      bucket?: string;
      topic_filter?: string | null;
    };

    try {
      body = await req.json();
    } catch {
      return withCors(json(400, { error: "Invalid JSON body" }));
    }

    const { figure_ids, start_date, end_date, bucket, topic_filter } = body;

    // Validate figure_ids
    if (!Array.isArray(figure_ids)) {
      return withCors(json(400, { error: "figure_ids must be an array" }));
    }
    if (figure_ids.length < MIN_FIGURES) {
      return withCors(
        json(400, {
          error: `Minimum ${MIN_FIGURES} figures required for convergence`,
        })
      );
    }
    if (figure_ids.length > MAX_FIGURES) {
      return withCors(
        json(400, { error: `Maximum ${MAX_FIGURES} figures allowed` })
      );
    }
    const uniqueIds = [...new Set(figure_ids)];
    if (uniqueIds.length < MIN_FIGURES) {
      return withCors(
        json(400, { error: "At least 2 unique figure_ids required" })
      );
    }
    for (const id of uniqueIds) {
      if (typeof id !== "string" || !UUID_REGEX.test(id)) {
        const safe = Array.from(String(id)).slice(0, 40).join("");
        return withCors(json(400, { error: `Invalid figure_id: ${safe}` }));
      }
    }

    // Validate dates
    if (typeof start_date !== "string" || !ISO_DATE_REGEX.test(start_date)) {
      return withCors(
        json(400, { error: "start_date must be YYYY-MM-DD format" })
      );
    }
    if (typeof end_date !== "string" || !ISO_DATE_REGEX.test(end_date)) {
      return withCors(
        json(400, { error: "end_date must be YYYY-MM-DD format" })
      );
    }
    if (start_date >= end_date) {
      return withCors(
        json(400, { error: "start_date must be before end_date" })
      );
    }

    // V1.0.1 FIX4: Max date range validation
    if (daysBetween(start_date, end_date) > MAX_DATE_RANGE_DAYS) {
      return withCors(
        json(400, {
          error: `Date range cannot exceed ${MAX_DATE_RANGE_DAYS} days`,
        })
      );
    }

    // Validate bucket
    if (!VALID_BUCKETS.has(bucket as string)) {
      return withCors(
        json(400, { error: 'bucket must be "week" or "month"' })
      );
    }

    // V1.0.1 FIX10: Normalize empty topic_filter to null
    const topicFilter =
      topic_filter && typeof topic_filter === "string"
        ? topic_filter.trim() || null
        : null;

    // ── Log request start ─────────────────────────────────────────────────
    // V1.0.1 FIX1: Pipeline event logging
    await logPipelineEvent(serviceClient, requestId, "START", {
      figure_count: uniqueIds.length,
      bucket: bucket as string,
      date_range: { start: start_date, end: end_date },
      topic_filter: topicFilter,
      user_id: user.id,
    });

    // ── B2-1: Server-side feature flag enforcement ─────────────────────────
    // Defense-in-depth: verify ENABLE_NARRATIVE_SYNC is active, not just tier.
    const { data: flagData } = await serviceClient
      .from("feature_flags")
      .select("enabled")
      .eq("flag_name", "ENABLE_NARRATIVE_SYNC")
      .single();

    if (!flagData || !flagData.enabled) {
      return withCors(json(503, { error: "Service temporarily unavailable" }));
    }

    // ── Fetch figures ────────────────────────────────────────────────────
    const figuresResult = await serviceClient
      .from("figures")
      .select("figure_id, name")
      .in("figure_id", uniqueIds)
      .eq("is_active", true);

    // ── Validate figures ──────────────────────────────────────────────────
    if (figuresResult.error) {
      console.error("[get-narrative-sync] Figures fetch failed", {
        requestId,
        error: figuresResult.error.message,
      });
      return withCors(json(500, { error: "Internal error" }));
    }

    const figuresData = figuresResult.data;
    if (!figuresData || figuresData.length < MIN_FIGURES) {
      return withCors(
        json(400, {
          error: `Only ${figuresData?.length ?? 0} active figures found (need >= ${MIN_FIGURES})`,
        })
      );
    }

    const figureMap = new Map<string, string>();
    for (const f of figuresData) {
      figureMap.set(f.figure_id, f.name);
    }
    const validFigureIds = [...figureMap.keys()];

    // ── Paginated statement fetch (A2-C1: avoids PostgREST 1000-row limit) ─
    const PAGE_SIZE = 1000;
    const statements: any[] = [];
    let pageFrom = 0;
    let hasMore = true;

    while (hasMore) {
      let query = serviceClient
        .from("statements")
        .select(
          `
          statement_id,
          figure_id,
          timestamp,
          topics,
          consensus!inner (
            framing_consensus,
            signal_rank,
            repetition_avg,
            novelty_avg,
            affective_language_rate_avg,
            topic_entropy_avg
          )
        `
        )
        .in("figure_id", uniqueIds)
        .eq("is_revoked", false)
        .gte("timestamp", start_date)
        .lt("timestamp", end_date)
        .order("timestamp", { ascending: true })
        .range(pageFrom, pageFrom + PAGE_SIZE - 1);

      if (topicFilter) {
        query = query.contains("topics", [topicFilter]);
      }

      const { data, error } = await query;

      if (error) {
        console.error("[get-narrative-sync] Statements query failed", {
          requestId,
          page: pageFrom,
          error: error.message,
        });
        return withCors(json(500, { error: "Internal error" }));
      }

      if (data && data.length > 0) {
        statements.push(...data);
      }

      // If we got fewer rows than page size, we've exhausted all data
      hasMore = (data?.length ?? 0) === PAGE_SIZE;
      pageFrom += PAGE_SIZE;
    }

    // V1.0.1 FIX8: Clean empty response (not an error)
    if (statements.length === 0) {
      const elapsed = Math.round(performance.now() - startTime);
      await logPipelineEvent(serviceClient, requestId, "SUCCESS", {
        statements_found: 0,
        elapsed_ms: elapsed,
      });

      return withCors(
        json(200, {
          request_id: requestId,
          figures: validFigureIds.map((id) => ({
            figure_id: id,
            figure_name: figureMap.get(id) || "Unknown",
            timeline: [],
          })),
          convergence_events: [],
          metric_proximity_events: [],
          metrics: {
            total_buckets: 0,
            convergence_buckets: 0,
            convergence_rate: 0,
            most_converged_framing: null,
            most_converged_pair: null,
            most_converged_pair_names: null,
            pair_convergence_counts: {},
            metric_proximity_count: 0,
            total_statements_analyzed: 0,
            figure_count: validFigureIds.length,
            date_range: { start: start_date, end: end_date },
            elapsed_ms: elapsed,
          },
        }),
        300 // V1.0.1 FIX6: 5min cache
      );
    }

    // ── Filter statements to valid figures only ───────────────────────────
    // Statements query used uniqueIds (user input) but some may not be
    // active. Filter to validFigureIds (confirmed active).
    const validIdSet = new Set(validFigureIds);
    const filteredStatements = statements.filter((s: any) =>
      validIdSet.has(s.figure_id)
    );

    // ── Bucket statements ─────────────────────────────────────────────────
    // Group by figure_id + time bucket. Compute per-bucket aggregates.

    interface BucketedData {
      bucket: string;
      dominantFraming: string;
      framingDistribution: Record<string, number>;
      statementCount: number;
      // Running sums + independent denominators (A2-C2: null-safe)
      sumSignalRank: number;
      sumRepetition: number;
      sumNovelty: number;
      sumAffective: number;
      sumEntropy: number;
      countSignalRank: number;
      countRepetition: number;
      countNovelty: number;
      countAffective: number;
      countEntropy: number;
      // Finalized averages (set after loop)
      avgSignalRank: number;
      avgRepetition: number;
      avgNovelty: number;
      avgAffective: number;
      avgEntropy: number;
    }

    const figureBuckets = new Map<string, Map<string, BucketedData>>();
    const allBuckets = new Set<string>();

    for (const stmt of filteredStatements) {
      const figId = stmt.figure_id;
      // consensus is returned as object (inner join = exactly one)
      const c = Array.isArray(stmt.consensus)
        ? stmt.consensus[0]
        : stmt.consensus;
      if (!c || !c.framing_consensus) continue;

      // Compute bucket key
      const ts = new Date(stmt.timestamp);
      let bucketKey: string;

      if (bucket === "month") {
        bucketKey = new Date(
          Date.UTC(ts.getUTCFullYear(), ts.getUTCMonth(), 1)
        ).toISOString();
      } else {
        // week: truncate to Monday (ISO week start)
        const day = ts.getUTCDay(); // 0=Sun
        const diff = day === 0 ? 6 : day - 1;
        const monday = new Date(ts);
        monday.setUTCDate(ts.getUTCDate() - diff);
        monday.setUTCHours(0, 0, 0, 0);
        bucketKey = monday.toISOString();
      }

      allBuckets.add(bucketKey);

      if (!figureBuckets.has(figId)) {
        figureBuckets.set(figId, new Map());
      }
      const buckets = figureBuckets.get(figId)!;

      if (!buckets.has(bucketKey)) {
        buckets.set(bucketKey, {
          bucket: bucketKey,
          dominantFraming: "",
          framingDistribution: {},
          statementCount: 0,
          sumSignalRank: 0, sumRepetition: 0, sumNovelty: 0,
          sumAffective: 0, sumEntropy: 0,
          countSignalRank: 0, countRepetition: 0, countNovelty: 0,
          countAffective: 0, countEntropy: 0,
          avgSignalRank: 0, avgRepetition: 0, avgNovelty: 0,
          avgAffective: 0, avgEntropy: 0,
        });
      }

      const bd = buckets.get(bucketKey)!;
      bd.statementCount++;

      const framing = String(c.framing_consensus);
      bd.framingDistribution[framing] =
        (bd.framingDistribution[framing] || 0) + 1;

      // A2-C2: Null-safe metric accumulation (independent denominators).
      // Only add non-null values. Prevents Number(null) = 0 from tanking averages.
      if (c.signal_rank !== null && c.signal_rank !== undefined) {
        bd.sumSignalRank += Number(c.signal_rank);
        bd.countSignalRank++;
      }
      if (c.repetition_avg !== null && c.repetition_avg !== undefined) {
        bd.sumRepetition += Number(c.repetition_avg);
        bd.countRepetition++;
      }
      if (c.novelty_avg !== null && c.novelty_avg !== undefined) {
        bd.sumNovelty += Number(c.novelty_avg);
        bd.countNovelty++;
      }
      if (c.affective_language_rate_avg !== null && c.affective_language_rate_avg !== undefined) {
        bd.sumAffective += Number(c.affective_language_rate_avg);
        bd.countAffective++;
      }
      if (c.topic_entropy_avg !== null && c.topic_entropy_avg !== undefined) {
        bd.sumEntropy += Number(c.topic_entropy_avg);
        bd.countEntropy++;
      }
    }

    // Finalize averages + dominant framing
    for (const [, buckets] of figureBuckets) {
      for (const [, bd] of buckets) {
        // A2-C2: Per-metric denominators (null-safe averaging)
        bd.avgSignalRank = bd.countSignalRank > 0
          ? round2(bd.sumSignalRank / bd.countSignalRank) : 0;
        bd.avgRepetition = bd.countRepetition > 0
          ? round2(bd.sumRepetition / bd.countRepetition) : 0;
        bd.avgNovelty = bd.countNovelty > 0
          ? round2(bd.sumNovelty / bd.countNovelty) : 0;
        bd.avgAffective = bd.countAffective > 0
          ? round2(bd.sumAffective / bd.countAffective) : 0;
        bd.avgEntropy = bd.countEntropy > 0
          ? round2(bd.sumEntropy / bd.countEntropy) : 0;
        // V1.0.1 FIX3: Deterministic dominant framing (alphabetical on tie)
        let maxCount = 0;
        let dominant = "";
        const sortedFramings = Object.entries(bd.framingDistribution).sort(
          (a, b) => a[0].localeCompare(b[0])
        );
        for (const [framing, count] of sortedFramings) {
          if (count > maxCount) {
            maxCount = count;
            dominant = framing;
          }
        }
        bd.dominantFraming = dominant;
      }
    }

    // ── Build figures response ────────────────────────────────────────────
    const figuresResponse = validFigureIds.map((figId) => {
      const buckets = figureBuckets.get(figId);
      const timeline = buckets
        ? [...buckets.values()].sort(
            (a, b) =>
              new Date(a.bucket).getTime() - new Date(b.bucket).getTime()
          )
        : [];

      return {
        figure_id: figId,
        figure_name: figureMap.get(figId) || "Unknown",
        timeline: timeline.map((bd) => ({
          bucket: bd.bucket,
          dominant_framing: bd.dominantFraming,
          framing_distribution: bd.framingDistribution,
          statement_count: bd.statementCount,
          avg_signal_rank: bd.avgSignalRank,
          avg_repetition: bd.avgRepetition,
          avg_novelty: bd.avgNovelty,
          avg_affective: bd.avgAffective,
          avg_entropy: bd.avgEntropy,
        })),
      };
    });

    // ── Convergence detection ─────────────────────────────────────────────
    // For each bucket, find framings shared by 2+ figures.
    // A convergence event = same dominant_framing in same bucket for >=2 figures.

    interface ConvergenceEvent {
      bucket: string;
      framing: string;
      figureIds: string[];
      figureNames: string[];
      combinedStatementCount: number;
      avgSignalRank: number;
    }

    // V1.0.1 FIX5: Metric proximity detection
    interface MetricProximityEvent {
      bucket: string;
      figureIds: string[];
      figureNames: string[];
      signalRanks: number[];
      delta: number;
    }

    const convergenceEvents: ConvergenceEvent[] = [];
    const metricProximityEvents: MetricProximityEvent[] = [];
    const convergenceBuckets = new Set<string>();
    const pairCounts = new Map<string, number>();

    for (const bucketKey of [...allBuckets].sort()) {
      // Collect dominant framing per figure in this bucket
      const framingToFigures = new Map<
        string,
        { figId: string; statementCount: number; signalRank: number }[]
      >();

      // Collect signal ranks per figure for proximity detection
      const bucketSignalRanks: { figId: string; rank: number }[] = [];

      for (const figId of validFigureIds) {
        const buckets = figureBuckets.get(figId);
        if (!buckets) continue;
        const bd = buckets.get(bucketKey);
        if (!bd || !bd.dominantFraming) continue;

        const framing = bd.dominantFraming;
        if (!framingToFigures.has(framing)) {
          framingToFigures.set(framing, []);
        }
        framingToFigures.get(framing)!.push({
          figId,
          statementCount: bd.statementCount,
          signalRank: bd.avgSignalRank,
        });

        bucketSignalRanks.push({ figId, rank: bd.avgSignalRank });
      }

      // Find framing convergences (framing shared by >=2 figures)
      for (const [framing, entries] of framingToFigures) {
        if (entries.length < 2) continue;

        convergenceBuckets.add(bucketKey);

        const totalStatements = entries.reduce(
          (sum, e) => sum + e.statementCount,
          0
        );
        // A2-I1: Weighted average (statement count as weight, not simple mean)
        const avgRank = totalStatements > 0
          ? entries.reduce(
              (sum, e) => sum + e.signalRank * e.statementCount,
              0
            ) / totalStatements
          : 0;

        convergenceEvents.push({
          bucket: bucketKey,
          framing,
          figureIds: entries.map((e) => e.figId),
          figureNames: entries.map(
            (e) => figureMap.get(e.figId) || "Unknown"
          ),
          combinedStatementCount: totalStatements,
          avgSignalRank: round2(avgRank),
        });

        // Track pairwise convergence
        for (let i = 0; i < entries.length; i++) {
          for (let j = i + 1; j < entries.length; j++) {
            const pairKey = [entries[i].figId, entries[j].figId]
              .sort()
              .join("|");
            pairCounts.set(pairKey, (pairCounts.get(pairKey) || 0) + 1);
          }
        }
      }

      // V1.0.1 FIX5: Metric proximity: find pairs with signal_rank within threshold
      for (let i = 0; i < bucketSignalRanks.length; i++) {
        for (let j = i + 1; j < bucketSignalRanks.length; j++) {
          const a = bucketSignalRanks[i];
          const b = bucketSignalRanks[j];
          const delta = Math.abs(a.rank - b.rank);
          if (delta <= METRIC_PROXIMITY_THRESHOLD) {
            metricProximityEvents.push({
              bucket: bucketKey,
              figureIds: [a.figId, b.figId].sort(),
              figureNames: [a.figId, b.figId]
                .sort()
                .map((id) => figureMap.get(id) || "Unknown"),
              signalRanks: [round2(a.rank), round2(b.rank)],
              delta: round2(delta),
            });
          }
        }
      }
    }

    // ── Compute metrics ───────────────────────────────────────────────────
    const totalBuckets = allBuckets.size;
    const convergenceBucketCount = convergenceBuckets.size;
    const convergenceRate =
      totalBuckets > 0 ? round3(convergenceBucketCount / totalBuckets) : 0;

    // Most converged framing (deterministic: alphabetical on tie)
    const framingConvergenceCounts = new Map<string, number>();
    for (const event of convergenceEvents) {
      framingConvergenceCounts.set(
        event.framing,
        (framingConvergenceCounts.get(event.framing) || 0) + 1
      );
    }
    let mostConvergedFraming = "";
    let maxFramingCount = 0;
    // V1.0.1 FIX3: Sort alphabetically for deterministic tie-break
    const sortedFramingEntries = [...framingConvergenceCounts.entries()].sort(
      (a, b) => a[0].localeCompare(b[0])
    );
    for (const [framing, count] of sortedFramingEntries) {
      if (count > maxFramingCount) {
        maxFramingCount = count;
        mostConvergedFraming = framing;
      }
    }

    // Most converged pair (deterministic: sorted pair key on tie)
    let mostConvergedPair: string[] = [];
    let mostConvergedPairNames: string[] = [];
    let maxPairCount = 0;
    const sortedPairEntries = [...pairCounts.entries()].sort((a, b) =>
      a[0].localeCompare(b[0])
    );
    for (const [pairKey, count] of sortedPairEntries) {
      if (count > maxPairCount) {
        maxPairCount = count;
        const ids = pairKey.split("|");
        mostConvergedPair = ids;
        mostConvergedPairNames = ids.map(
          (id) => figureMap.get(id) || "Unknown"
        );
      }
    }

    const pairConvergenceObj: Record<string, number> = {};
    for (const [key, count] of pairCounts) {
      pairConvergenceObj[key] = count;
    }

    // V1.0.1 FIX2: Request timing
    const elapsedMs = Math.round(performance.now() - startTime);

    // V1.0.1 FIX1: Log success
    await logPipelineEvent(serviceClient, requestId, "SUCCESS", {
      figure_count: validFigureIds.length,
      statement_count: filteredStatements.length,
      convergence_events: convergenceEvents.length,
      metric_proximity_events: metricProximityEvents.length,
      elapsed_ms: elapsedMs,
    });

    console.log("[get-narrative-sync] Complete", {
      requestId,
      figures: validFigureIds.length,
      statements: filteredStatements.length,
      convergences: convergenceEvents.length,
      elapsed_ms: elapsedMs,
    });

    // ── Final response ────────────────────────────────────────────────────
    const response = {
      request_id: requestId,
      figures: figuresResponse,
      convergence_events: convergenceEvents.map((e) => ({
        bucket: e.bucket,
        framing: e.framing,
        figure_ids: e.figureIds,
        figure_names: e.figureNames,
        combined_statement_count: e.combinedStatementCount,
        avg_signal_rank: e.avgSignalRank,
      })),
      metric_proximity_events: metricProximityEvents.map((e) => ({
        bucket: e.bucket,
        figure_ids: e.figureIds,
        figure_names: e.figureNames,
        signal_ranks: e.signalRanks,
        delta: e.delta,
      })),
      metrics: {
        total_buckets: totalBuckets,
        convergence_buckets: convergenceBucketCount,
        convergence_rate: convergenceRate,
        most_converged_framing: mostConvergedFraming || null,
        most_converged_pair:
          mostConvergedPair.length > 0 ? mostConvergedPair : null,
        most_converged_pair_names:
          mostConvergedPairNames.length > 0 ? mostConvergedPairNames : null,
        pair_convergence_counts: pairConvergenceObj,
        metric_proximity_count: metricProximityEvents.length,
        total_statements_analyzed: filteredStatements.length,
        figure_count: validFigureIds.length,
        date_range: { start: start_date, end: end_date },
        elapsed_ms: elapsedMs,
      },
    };

    return withCors(json(200, response), 300); // V1.0.1 FIX6: 5min cache
  } catch (err) {
    const elapsedMs = Math.round(performance.now() - startTime);
    console.error("[get-narrative-sync] Unhandled error", {
      requestId,
      message: (err as Error)?.message,
      elapsed_ms: elapsedMs,
    });

    // Log error to pipeline events (best-effort, internal catch handles failures)
    if (serviceClient) {
      await logPipelineEvent(serviceClient, requestId, "ERROR", {
        message: (err as Error)?.message || "Unknown error",
        elapsed_ms: elapsedMs,
      });
    }

    return withCors(json(500, { error: "Internal error" }));
  }
});
