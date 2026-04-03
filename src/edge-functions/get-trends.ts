// ========================================================================
// SUPABASE EDGE FUNCTION: get-trends (A14C)
// Routes to get_historical_trends or get_framing_distribution RPCs.
// Presence of `metric` field → timeline route. Absence → radar route.
// ========================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-entitlement-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Period string to interval params
function periodToDates(period: string): { start: string; end: string } {
  const now = new Date();
  const end = now.toISOString();
  let start: Date;
  switch (period) {
    case "30d":
      start = new Date(now.getTime() - 30 * 86400000);
      break;
    case "90d":
      start = new Date(now.getTime() - 90 * 86400000);
      break;
    case "1y":
      start = new Date(now.getTime() - 365 * 86400000);
      break;
    default:
      start = new Date(now.getTime() - 90 * 86400000);
  }
  return { start: start.toISOString(), end };
}

// Period to bucket granularity
function periodToBucket(period: string, granularity?: string): string {
  if (granularity) return granularity;
  switch (period) {
    case "30d": return "week";
    case "90d": return "month";
    case "1y": return "month";
    default: return "month";
  }
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
    const body = await req.json().catch(() => ({}));
    const figureId = body.figure_id;
    const period = body.period || "90d";
    const metric = body.metric; // presence determines route

    if (!figureId) {
      return json({ error: "figure_id is required" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const dates = periodToDates(period);

    if (metric) {
      // ── Route 1: Metric Timeline ──────────────────────────────
      const bucket = periodToBucket(period, body.granularity);

      const { data, error } = await supabase.rpc("get_historical_trends", {
        p_figure_id: figureId,
        p_start_date: dates.start,
        p_end_date: dates.end,
        p_bucket: bucket,
      });

      if (error) {
        console.error("get_historical_trends error:", error);
        return json({ error: error.message }, 500);
      }

      // Map RPC rows to metric-specific data points
      const metricColumn = `avg_${metric}`;
      const dataPoints = (data || []).map((row: Record<string, unknown>) => ({
        period: row.period,
        value: row[metricColumn] ?? null,
        count: row.statement_count ?? 0,
      }));

      return json({
        figure_id: figureId,
        metric,
        period,
        data_points: dataPoints,
      });
    } else {
      // ── Route 2: Framing Radar ────────────────────────────────
      const { data: currentData, error: currentErr } = await supabase.rpc(
        "get_framing_distribution",
        {
          p_figure_id: figureId,
          p_start_date: dates.start,
          p_end_date: dates.end,
        }
      );

      if (currentErr) {
        console.error("get_framing_distribution error:", currentErr);
        return json({ error: currentErr.message }, 500);
      }

      // Build current period map (label → proportion 0.0-1.0)
      const current: Record<string, number> = {};
      let totalStatements = 0;
      for (const row of currentData || []) {
        current[row.framing_label] = parseFloat(row.percentage) / 100;
        totalStatements += parseInt(row.statement_count) || 0;
      }

      // Previous period for comparison
      const prevDates = periodToDates(
        period === "30d" ? "30d" : period === "90d" ? "90d" : "1y"
      );
      const prevEnd = dates.start; // previous period ends where current starts
      const prevDuration = new Date(dates.end).getTime() - new Date(dates.start).getTime();
      const prevStart = new Date(new Date(prevEnd).getTime() - prevDuration).toISOString();

      const { data: prevData } = await supabase.rpc(
        "get_framing_distribution",
        {
          p_figure_id: figureId,
          p_start_date: prevStart,
          p_end_date: prevEnd,
        }
      );

      let previous: Record<string, number> | null = null;
      if (prevData && prevData.length > 0) {
        previous = {};
        for (const row of prevData) {
          previous[row.framing_label] = parseFloat(row.percentage) / 100;
        }
      }

      return json({
        figure_id: figureId,
        period,
        current,
        previous,
        total_statements: totalStatements,
      });
    }
  } catch (err) {
    console.error("get-trends fatal:", err);
    return json({ error: String(err) }, 500);
  }
});
