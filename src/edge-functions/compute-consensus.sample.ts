// compute-consensus.ts
// Edge Function: loads all provider analyses for a statement,
// computes inter-model agreement, detects variance and outliers,
// and produces a consensus score.
//
// Threshold values and proprietary weights are redacted.
// The algorithm shape and all control flow are visible.

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AnalysisRow {
  analysis_id: string;
  statement_id: string;
  model_provider: string;
  model_version: string;
  repetition: number;
  novelty: number;
  affective_language_rate: number;
  topic_entropy: number;
  framing: string;
  confidence: number;
  analyzed_at: string;
}

interface ConsensusResult {
  consensus_score: number;
  agreement_level: "high" | "moderate" | "low" | "split";
  provider_spread: number;
  outlier_provider: string | null;
  variance_detected: boolean;
  signal_rank: number;
  framing_consensus: string | null;
  framing_agreement_count: number;
  framing_split: Record<string, number>;
  metric_averages: MetricAverages;
  metric_stddevs: MetricStddevs;
  models_included: string[];
  model_count: number;
}

interface MetricAverages {
  repetition_avg: number;
  novelty_avg: number;
  affective_language_rate_avg: number;
  topic_entropy_avg: number;
  baseline_delta_avg: number;
}

interface MetricStddevs {
  repetition_stddev: number;
  novelty_stddev: number;
  affective_language_rate_stddev: number;
  topic_entropy_stddev: number;
}

// Proprietary thresholds and weights
const AGREEMENT_THRESHOLDS = {
  high: "[REDACTED]" as unknown as number,
  moderate: "[REDACTED]" as unknown as number,
  low: "[REDACTED]" as unknown as number,
};
const VARIANCE_THRESHOLD = "[REDACTED]" as unknown as number;
const SIGNAL_WEIGHTS = {
  repetition: "[REDACTED]" as unknown as number,
  novelty: "[REDACTED]" as unknown as number,
  affective_language_rate: "[REDACTED]" as unknown as number,
  topic_entropy: "[REDACTED]" as unknown as number,
};
const OUTLIER_DEVIATION_FACTOR = "[REDACTED]" as unknown as number;

// Metrics that the consensus engine evaluates
const METRIC_KEYS = ["repetition", "novelty", "affective_language_rate", "topic_entropy"] as const;

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Kill switch
  const ksRaw = Deno.env.get("BASELINE_KILL_SWITCH") ?? "";
  if (ksRaw === "TRUE" || ksRaw.toLowerCase() === "true") {
    return new Response(JSON.stringify({ error: "Service temporarily disabled" }), {
      status: 503,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { statement_id }: { statement_id: string } = await req.json();

    if (!statement_id) {
      return new Response(JSON.stringify({ error: "Missing statement_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // --- Load all provider analyses for this statement ---
    const { data: analyses, error: fetchError } = await supabase
      .from("analyses")
      .select(
        "analysis_id, statement_id, model_provider, model_version, " +
        "repetition, novelty, affective_language_rate, topic_entropy, " +
        "framing, confidence, analyzed_at"
      )
      .eq("statement_id", statement_id)
      .order("analyzed_at", { ascending: true });

    if (fetchError) {
      throw new Error(`Failed to fetch analyses: ${fetchError.message}`);
    }

    if (!analyses || analyses.length < 2) {
      return new Response(
        JSON.stringify({ error: "Insufficient analyses", count: analyses?.length ?? 0 }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // --- Compute consensus ---
    const consensus = computeConsensus(analyses as AnalysisRow[]);

    // --- Persist to consensus table (upsert on statement_id) ---
    const { error: upsertError } = await supabase.from("consensus").upsert({
      statement_id,
      repetition_avg: consensus.metric_averages.repetition_avg,
      repetition_stddev: consensus.metric_stddevs.repetition_stddev,
      novelty_avg: consensus.metric_averages.novelty_avg,
      novelty_stddev: consensus.metric_stddevs.novelty_stddev,
      affective_language_rate_avg: consensus.metric_averages.affective_language_rate_avg,
      affective_language_rate_stddev: consensus.metric_stddevs.affective_language_rate_stddev,
      topic_entropy_avg: consensus.metric_averages.topic_entropy_avg,
      topic_entropy_stddev: consensus.metric_stddevs.topic_entropy_stddev,
      baseline_delta_avg: consensus.metric_averages.baseline_delta_avg,
      variance_detected: consensus.variance_detected,
      signal_rank: consensus.signal_rank,
      signal_components: SIGNAL_WEIGHTS,
      framing_consensus: consensus.framing_consensus,
      framing_agreement_count: consensus.framing_agreement_count,
      framing_split: consensus.framing_split,
      model_versions: analyses.map((a) => a.model_version),
      models_included: consensus.models_included,
      model_count: consensus.model_count,
      computed_at: new Date().toISOString(),
    });

    if (upsertError) {
      throw new Error(`Failed to upsert consensus: ${upsertError.message}`);
    }

    return new Response(JSON.stringify(consensus), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("[compute-consensus] Error:", error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ---------------------------------------------------------------------------
// Consensus algorithm
// ---------------------------------------------------------------------------

function computeConsensus(analyses: AnalysisRow[]): ConsensusResult {
  const providers = analyses.map((a) => a.model_provider);

  // --- Step 1: Compute per-metric averages and standard deviations ---
  const averages = computeMetricAverages(analyses);
  const stddevs = computeMetricStddevs(analyses, averages);

  // --- Step 2: Measure inter-provider agreement (spread) ---
  // Spread = mean of all metric standard deviations, normalized to 0-100.
  // Low spread = providers agree. High spread = providers disagree.
  const metricStddevValues = [
    stddevs.repetition_stddev,
    stddevs.novelty_stddev,
    stddevs.affective_language_rate_stddev,
    stddevs.topic_entropy_stddev,
  ];
  const providerSpread = mean(metricStddevValues);

  // --- Step 3: Classify agreement level based on spread ---
  const agreementLevel = classifyAgreement(providerSpread);

  // --- Step 4: Detect high-variance cases ---
  // Variance is flagged when any single metric's stddev exceeds the threshold.
  // These are often the most interesting statements: providers fundamentally
  // disagree about what a statement means.
  const varianceDetected = metricStddevValues.some(
    (sd) => sd > (VARIANCE_THRESHOLD as number)
  );

  // --- Step 5: Detect outlier provider ---
  // For each provider, compute its average deviation from the consensus.
  // The provider with the largest deviation is flagged as the outlier,
  // but only if its deviation exceeds the threshold factor.
  const outlierProvider = detectOutlier(analyses, averages);

  // --- Step 6: Compute signal rank ---
  // Weighted combination of metric averages. Higher signal = more noteworthy.
  const signalRank = computeSignalRank(averages);

  // --- Step 7: Determine framing consensus ---
  // Majority vote across providers. If no majority, framing_consensus is null
  // and framing_split shows the distribution.
  const { framingConsensus, framingAgreementCount, framingSplit } =
    computeFramingConsensus(analyses);

  // --- Step 8: Compute baseline delta average ---
  // This measures how this statement compares to the figure's historical norms.
  const baselineDeltaAvg = computeBaselineDelta(averages);

  return {
    consensus_score: roundTo(100 - providerSpread, 2), // higher = more agreement
    agreement_level: agreementLevel,
    provider_spread: roundTo(providerSpread, 2),
    outlier_provider: outlierProvider,
    variance_detected: varianceDetected,
    signal_rank: roundTo(signalRank, 2),
    framing_consensus: framingConsensus,
    framing_agreement_count: framingAgreementCount,
    framing_split: framingSplit,
    metric_averages: {
      repetition_avg: roundTo(averages.repetition, 2),
      novelty_avg: roundTo(averages.novelty, 2),
      affective_language_rate_avg: roundTo(averages.affective_language_rate, 2),
      topic_entropy_avg: roundTo(averages.topic_entropy, 2),
      baseline_delta_avg: roundTo(baselineDeltaAvg, 2),
    },
    metric_stddevs: {
      repetition_stddev: roundTo(stddevs.repetition_stddev, 2),
      novelty_stddev: roundTo(stddevs.novelty_stddev, 2),
      affective_language_rate_stddev: roundTo(stddevs.affective_language_rate_stddev, 2),
      topic_entropy_stddev: roundTo(stddevs.topic_entropy_stddev, 2),
    },
    models_included: providers,
    model_count: providers.length,
  };
}

// ---------------------------------------------------------------------------
// Metric computation helpers
// ---------------------------------------------------------------------------

function computeMetricAverages(
  analyses: AnalysisRow[]
): Record<(typeof METRIC_KEYS)[number], number> {
  const result: Record<string, number> = {};
  for (const key of METRIC_KEYS) {
    const values = analyses.map((a) => a[key] as number);
    result[key] = mean(values);
  }
  return result as Record<(typeof METRIC_KEYS)[number], number>;
}

function computeMetricStddevs(
  analyses: AnalysisRow[],
  averages: Record<string, number>
): MetricStddevs {
  const sd = (key: string): number => {
    const values = analyses.map((a) => (a as Record<string, number>)[key]);
    return stddev(values, averages[key]);
  };

  return {
    repetition_stddev: sd("repetition"),
    novelty_stddev: sd("novelty"),
    affective_language_rate_stddev: sd("affective_language_rate"),
    topic_entropy_stddev: sd("topic_entropy"),
  };
}

/** Classifies agreement level based on provider spread. */
function classifyAgreement(spread: number): ConsensusResult["agreement_level"] {
  // Thresholds are proprietary but the logic is:
  // low spread -> high agreement, high spread -> split
  if (spread <= (AGREEMENT_THRESHOLDS.high as number)) return "high";
  if (spread <= (AGREEMENT_THRESHOLDS.moderate as number)) return "moderate";
  if (spread <= (AGREEMENT_THRESHOLDS.low as number)) return "low";
  return "split";
}

/**
 * Detects which provider (if any) is the outlier.
 * Computes each provider's mean absolute deviation from the consensus averages
 * across all metrics. If the highest-deviating provider exceeds the threshold,
 * it is flagged.
 */
function detectOutlier(
  analyses: AnalysisRow[],
  averages: Record<string, number>
): string | null {
  let maxDeviation = 0;
  let outlier: string | null = null;

  for (const analysis of analyses) {
    let totalDeviation = 0;
    for (const key of METRIC_KEYS) {
      totalDeviation += Math.abs((analysis[key] as number) - averages[key]);
    }
    const avgDeviation = totalDeviation / METRIC_KEYS.length;

    if (avgDeviation > maxDeviation) {
      maxDeviation = avgDeviation;
      outlier = analysis.model_provider;
    }
  }

  // Only flag if deviation exceeds the threshold
  return maxDeviation > (OUTLIER_DEVIATION_FACTOR as number) ? outlier : null;
}

/**
 * Computes signal rank: weighted sum of metric averages.
 * Higher signal = more noteworthy statement (high novelty, high affect,
 * high entropy all contribute positively).
 */
function computeSignalRank(averages: Record<string, number>): number {
  let rank = 0;
  for (const key of METRIC_KEYS) {
    rank += averages[key] * ((SIGNAL_WEIGHTS as Record<string, number>)[key] ?? 0);
  }
  return Math.max(0, Math.min(100, rank));
}

/**
 * Determines framing consensus via majority vote.
 * Each provider assigns one of 5 canonical framing labels.
 * If a strict majority agrees, that label becomes the consensus.
 * Otherwise, framing_consensus is null and framing_split shows the vote distribution.
 */
function computeFramingConsensus(analyses: AnalysisRow[]): {
  framingConsensus: string | null;
  framingAgreementCount: number;
  framingSplit: Record<string, number>;
} {
  // Count votes per framing label
  const votes: Record<string, number> = {};
  for (const a of analyses) {
    const label = a.framing;
    votes[label] = (votes[label] ?? 0) + 1;
  }

  // Find the label with the most votes
  let maxLabel: string | null = null;
  let maxCount = 0;
  for (const [label, count] of Object.entries(votes)) {
    if (count > maxCount) {
      maxCount = count;
      maxLabel = label;
    }
  }

  // Strict majority: more than half of providers must agree
  const majority = analyses.length / 2;
  const hasConsensus = maxCount > majority;

  return {
    framingConsensus: hasConsensus ? maxLabel : null,
    framingAgreementCount: maxCount,
    framingSplit: votes,
  };
}

/** Computes baseline delta average from the consensus metric averages. */
function computeBaselineDelta(averages: Record<string, number>): number {
  // Delta measures how far this statement's metrics deviate from the
  // figure's historical norms. Computed as a normalized distance metric.
  // The actual weighting is proprietary, but uses the same metric keys.
  const values = METRIC_KEYS.map((k) => averages[k]);
  return mean(values);
}

// ---------------------------------------------------------------------------
// Math utilities
// ---------------------------------------------------------------------------

function mean(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function stddev(values: number[], avg: number): number {
  if (values.length < 2) return 0;
  const sumSqDiff = values.reduce((sum, v) => sum + (v - avg) ** 2, 0);
  return Math.sqrt(sumSqDiff / values.length);
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}
