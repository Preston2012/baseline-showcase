// analyze-statement.ts
// Edge Function: routes a statement to 4 AI providers in parallel,
// normalizes each response into a common schema, persists results,
// and logs cost per call.
//
// Prompt text is redacted. Everything else (control flow, validation,
// normalization, storage, cost tracking) is visible.

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AnalysisRequest {
  statement_id: string;
  figure_id: string;
  text: string;
  source_url: string;
}

/** Common output schema every provider's response is normalized into. */
interface AnalysisMetrics {
  repetition: number;       // 0-100: how much the figure repeats prior language
  novelty: number;          // 0-100: new framing or talking points
  affective_language_rate: number; // 0-100: emotional intensity of language
  topic_entropy: number;    // 0-100: breadth vs. focus of topics covered
  framing: string;          // one of 5 canonical labels (see below)
}

interface ProviderAnalysis {
  provider: "openai" | "anthropic" | "google" | "xai";
  metrics: AnalysisMetrics;
  confidence: number;       // 0-1: provider's self-reported confidence
  model_version: string;    // e.g. "gpt-4-0125-preview", "claude-3-opus-20240229"
  prompt_version: string;   // tracks which prompt revision was used
  raw_response: Record<string, unknown>;
  token_usage: { input: number; output: number };
}

/** Canonical framing labels (locked, matches A7A migration). */
const VALID_FRAMING_LABELS = new Set([
  "Adversarial / Oppositional",
  "Problem Identification",
  "Commitment / Forward-Looking",
  "Justification / Reactive",
  "Imperative / Directive",
]);

// ---------------------------------------------------------------------------
// Provider config
// ---------------------------------------------------------------------------

const PROVIDERS = [
  { name: "openai",    endpoint: "https://api.openai.com/v1/chat/completions",       envKey: "OPENAI_API_KEY" },
  { name: "anthropic", endpoint: "https://api.anthropic.com/v1/messages",             envKey: "ANTHROPIC_API_KEY" },
  { name: "google",    endpoint: "https://generativelanguage.googleapis.com/v1/models/gemini-pro:generateContent", envKey: "GOOGLE_API_KEY" },
  { name: "xai",       endpoint: "https://api.x.ai/v1/chat/completions",             envKey: "XAI_API_KEY" },
] as const;

/** Per-provider cost rates (USD per 1K tokens). Updated when pricing changes. */
const COST_PER_1K: Record<string, { input: number; output: number }> = {
  openai:    { input: 0.01,   output: 0.03   },
  anthropic: { input: 0.015,  output: 0.075  },
  google:    { input: 0.00025, output: 0.0005 },
  xai:       { input: 0.005,  output: 0.015  },
};

const PROMPT_TEXT = "[REDACTED: proprietary analysis prompt]";
const PROMPT_VERSION = "v3.2";
const REQUEST_TIMEOUT_MS = 30_000;

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
    const body: AnalysisRequest = await req.json();

    // --- Request validation ---
    if (!body.statement_id || !body.figure_id || !body.text) {
      return new Response(JSON.stringify({ error: "Missing required fields: statement_id, figure_id, text" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // --- Call all 4 providers in parallel ---
    const analyses = await Promise.allSettled(
      PROVIDERS.map((provider) =>
        analyzeWithProvider(provider.name, provider.endpoint, provider.envKey, body.text, body.figure_id)
      )
    );

    // --- Process results: store successes, log failures ---
    let successCount = 0;
    const errors: string[] = [];

    for (const [i, result] of analyses.entries()) {
      const providerName = PROVIDERS[i].name;

      if (result.status === "fulfilled") {
        await storeAnalysis(supabase, body.statement_id, providerName, result.value);
        await logCost(supabase, providerName, result.value);
        successCount++;
      } else {
        // Provider failure: log but don't block other providers
        errors.push(`${providerName}: ${result.reason?.message ?? "unknown error"}`);
        console.error(`[analyze-statement] ${providerName} failed:`, result.reason?.message);
      }
    }

    return new Response(
      JSON.stringify({
        success: successCount > 0,
        analyzed: successCount,
        failed: errors.length,
        errors: errors.length > 0 ? errors : undefined,
      }),
      {
        status: successCount > 0 ? 200 : 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("[analyze-statement] Handler error:", error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ---------------------------------------------------------------------------
// Provider call + normalization
// ---------------------------------------------------------------------------

async function analyzeWithProvider(
  provider: string,
  endpoint: string,
  envKey: string,
  text: string,
  figureId: string
): Promise<ProviderAnalysis> {
  const apiKey = Deno.env.get(envKey);
  if (!apiKey) throw new Error(`Missing env: ${envKey}`);

  // Build provider-specific request body
  const requestBody = buildProviderRequest(provider, text, figureId);

  // Call with timeout
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: buildProviderHeaders(provider, apiKey),
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`${provider} returned ${response.status}: ${errorBody.slice(0, 200)}`);
    }

    const raw = await response.json();

    // Extract text content from provider-specific response shape
    const content = extractContent(provider, raw);

    // Parse structured metrics from the provider's text response
    const metrics = parseMetrics(content);

    // Extract token usage from provider-specific response shape
    const tokenUsage = extractTokenUsage(provider, raw);

    return {
      provider: provider as ProviderAnalysis["provider"],
      metrics,
      confidence: extractConfidence(content),
      model_version: extractModelVersion(provider, raw),
      prompt_version: PROMPT_VERSION,
      raw_response: raw,
      token_usage: tokenUsage,
    };
  } finally {
    clearTimeout(timeout);
  }
}

/** Builds the request body in each provider's expected format. */
function buildProviderRequest(provider: string, text: string, figureId: string): Record<string, unknown> {
  // All providers receive the same prompt content with the statement text
  // and figure context. The prompt itself is proprietary.

  switch (provider) {
    case "openai":
    case "xai":
      // OpenAI and xAI share the chat completions format
      return {
        model: provider === "openai" ? "gpt-4-0125-preview" : "grok-2-latest",
        messages: [
          { role: "system", content: PROMPT_TEXT },
          { role: "user", content: `Figure: ${figureId}\n\nStatement: ${text}` },
        ],
        temperature: 0.1,
        response_format: { type: "json_object" },
      };

    case "anthropic":
      return {
        model: "claude-3-opus-20240229",
        max_tokens: 2048,
        system: PROMPT_TEXT,
        messages: [
          { role: "user", content: `Figure: ${figureId}\n\nStatement: ${text}` },
        ],
      };

    case "google":
      return {
        contents: [
          { parts: [{ text: `${PROMPT_TEXT}\n\nFigure: ${figureId}\n\nStatement: ${text}` }] },
        ],
        generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
      };

    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}

/** Builds auth headers per provider's API requirements. */
function buildProviderHeaders(provider: string, apiKey: string): Record<string, string> {
  const base: Record<string, string> = { "Content-Type": "application/json" };

  switch (provider) {
    case "openai":
    case "xai":
      return { ...base, Authorization: `Bearer ${apiKey}` };
    case "anthropic":
      return { ...base, "x-api-key": apiKey, "anthropic-version": "2023-06-01" };
    case "google":
      return { ...base, "x-goog-api-key": apiKey };
    default:
      return base;
  }
}

/** Extracts the text content from each provider's response envelope. */
function extractContent(provider: string, raw: Record<string, unknown>): string {
  switch (provider) {
    case "openai":
    case "xai": {
      const choices = raw.choices as { message: { content: string } }[];
      return choices?.[0]?.message?.content ?? "";
    }
    case "anthropic": {
      const content = raw.content as { text: string }[];
      return content?.[0]?.text ?? "";
    }
    case "google": {
      const candidates = raw.candidates as { content: { parts: { text: string }[] } }[];
      return candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    }
    default:
      return "";
  }
}

/** Extracts token usage from provider-specific response metadata. */
function extractTokenUsage(provider: string, raw: Record<string, unknown>): { input: number; output: number } {
  switch (provider) {
    case "openai":
    case "xai": {
      const usage = raw.usage as { prompt_tokens: number; completion_tokens: number } | undefined;
      return { input: usage?.prompt_tokens ?? 0, output: usage?.completion_tokens ?? 0 };
    }
    case "anthropic": {
      const usage = raw.usage as { input_tokens: number; output_tokens: number } | undefined;
      return { input: usage?.input_tokens ?? 0, output: usage?.output_tokens ?? 0 };
    }
    case "google": {
      const meta = raw.usageMetadata as { promptTokenCount: number; candidatesTokenCount: number } | undefined;
      return { input: meta?.promptTokenCount ?? 0, output: meta?.candidatesTokenCount ?? 0 };
    }
    default:
      return { input: 0, output: 0 };
  }
}

/** Extracts model version string from the provider response. */
function extractModelVersion(provider: string, raw: Record<string, unknown>): string {
  return (raw.model as string) ?? `${provider}-unknown`;
}

/**
 * Parses the structured JSON metrics from the provider's text response.
 * All providers are instructed to return JSON with the same metric keys.
 * This function validates ranges and normalizes the framing label.
 */
function parseMetrics(content: string): AnalysisMetrics {
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error("Provider returned non-JSON response");
  }

  const clamp = (v: unknown, min: number, max: number): number => {
    const n = Number(v);
    if (isNaN(n)) return min;
    return Math.max(min, Math.min(max, n));
  };

  const framing = String(parsed.framing ?? "");
  const normalizedFraming = VALID_FRAMING_LABELS.has(framing) ? framing : "Problem Identification";

  return {
    repetition: clamp(parsed.repetition, 0, 100),
    novelty: clamp(parsed.novelty, 0, 100),
    affective_language_rate: clamp(parsed.affective_language_rate, 0, 100),
    topic_entropy: clamp(parsed.topic_entropy, 0, 100),
    framing: normalizedFraming,
  };
}

/** Extracts a confidence value (0-1) from the parsed response. */
function extractConfidence(content: string): number {
  try {
    const parsed = JSON.parse(content);
    const c = Number(parsed.confidence);
    if (!isNaN(c) && c >= 0 && c <= 1) return c;
  } catch { /* fall through */ }
  return 0.5; // default confidence when not reported
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

async function storeAnalysis(
  supabase: ReturnType<typeof createClient>,
  statementId: string,
  provider: string,
  analysis: ProviderAnalysis
): Promise<void> {
  const row = {
    statement_id: statementId,
    model_provider: provider,
    model_version: analysis.model_version,
    prompt_version: analysis.prompt_version,
    repetition: analysis.metrics.repetition,
    novelty: analysis.metrics.novelty,
    affective_language_rate: analysis.metrics.affective_language_rate,
    topic_entropy: analysis.metrics.topic_entropy,
    framing: analysis.metrics.framing,
    confidence: analysis.confidence,
    analyzed_at: new Date().toISOString(),
  };

  // Insert into analyses table
  const { error: analysisError } = await supabase.from("analyses").insert(row);
  if (analysisError) {
    console.error(`[storeAnalysis] Failed to insert for ${provider}:`, analysisError.message);
    throw analysisError;
  }

  // Mirror to analyses_audit for provenance tracking
  const { error: auditError } = await supabase.from("analyses_audit").insert({
    ...row,
    raw_response: analysis.raw_response,
    audit_created_at: new Date().toISOString(),
  });
  if (auditError) {
    // Audit failure is logged but does not block the pipeline
    console.error(`[storeAnalysis] Audit insert failed for ${provider}:`, auditError.message);
  }
}

// ---------------------------------------------------------------------------
// Cost tracking
// ---------------------------------------------------------------------------

async function logCost(
  supabase: ReturnType<typeof createClient>,
  provider: string,
  analysis: ProviderAnalysis
): Promise<void> {
  const rates = COST_PER_1K[provider];
  if (!rates) return;

  const inputCost = (analysis.token_usage.input / 1000) * rates.input;
  const outputCost = (analysis.token_usage.output / 1000) * rates.output;

  const { error } = await supabase.from("cost_log").insert({
    provider,
    model: analysis.model_version,
    input_tokens: analysis.token_usage.input,
    output_tokens: analysis.token_usage.output,
    estimated_cost_usd: Math.round((inputCost + outputCost) * 1_000_000) / 1_000_000,
    logged_at: new Date().toISOString(),
  });

  if (error) {
    // Cost logging failure is non-blocking
    console.error(`[logCost] Failed for ${provider}:`, error.message);
  }
}
