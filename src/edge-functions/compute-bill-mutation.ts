// supabase/functions/compute-bill-mutation/index.ts
//
// PM-MT.3: Diff computation engine for Bill Mutation Timeline™.
//
// Takes a bill_id, fetches all versions, computes provision-level diffs
// between adjacent version pairs, scores magnitude via embeddings,
// populates spending crossover fields, writes results to PM-MT.1 tables.
//
// Pattern: Matches P2 (summarize-bill) architecture.
// Embeddings are transient (compute-and-discard, same as Provision Drift™).
//
// Auth: service_role only (called by PM-MT.2 n8n workflow)
// Cost: OpenAI embeddings only (~$0.001 per bill with 2 versions, 50 provisions)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') || '';
const OPENAI_EMBED_MODEL = Deno.env.get('OPENAI_EMBED_MODEL') || 'text-embedding-3-small';

const FEATURE_FLAG = 'ENABLE_BILL_MUTATION';

// Fuzzy match threshold for provision title similarity.
// 0.70 = at least 70% word overlap (Jaccard). Tuned to handle
// section renumbering ("Section 203" to "Section 204") while avoiding
// false positives on repetitive legislative language. Logged for audit.
const FUZZY_MATCH_THRESHOLD = 0.70;

// Stage ordering for sorting versions
const STAGE_ORDER: Record<string, number> = {
  introduced: 0,
  committee: 1,
  engrossed: 2,
  enrolled: 3,
};

// ── Types ──

interface BillVersion {
  version_id: string;
  bill_id: string;
  bill_title: string;
  stage: string;
  version_timestamp: string;
  provision_count: number;
  label: string | null;
  provisions_text: Provision[];
  chamber: string;
  congress_session: number;
  sponsor: string | null;
  source_url: string;
}

interface Provision {
  title: string;
  description: string;
  category: string;
  drift_score: number;
}

interface ProvisionMatch {
  type: 'added' | 'removed' | 'modified';
  provision_index: number;
  provision_title: string;
  category: string | null;
  old_text: string | null;
  new_text: string | null;
  magnitude: number;
  // Spending crossover
  spending_delta: number | null;
  old_spending: number | null;
  new_spending: number | null;
}

interface SpendingRow {
  spending_id: string;
  provision_index: number;
  provision_title: string;
  amount: number;
  category: string | null;
}

serve(async (req: Request) => {
  // ── CORS ──
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      },
    });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const startTime = Date.now();
  let totalEmbeddingTokens = 0;

  try {
    // ── Auth (service_role only) ──
    const authHeader = req.headers.get('Authorization');
    const expectedAuth = `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`;
    if (authHeader !== expectedAuth) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // ── Killswitch ──
    const { data: flagData } = await supabase
      .from('feature_flags')
      .select('enabled')
      .eq('flag_name', FEATURE_FLAG)
      .single();

    if (!flagData?.enabled) {
      return new Response(JSON.stringify({ error: 'Feature disabled' }), {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // ── Parse input ──
    const { p_bill_id } = await req.json();
    if (!p_bill_id || typeof p_bill_id !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing p_bill_id' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // ── Fetch all versions for this bill ──
    const { data: versions, error: vErr } = await supabase
      .from('bill_versions')
      .select('*')
      .eq('bill_id', p_bill_id)
      .order('version_timestamp', { ascending: true });

    if (vErr) throw new Error(`Failed to fetch versions: ${vErr.message}`);
    if (!versions || versions.length < 2) {
      return new Response(
        JSON.stringify({
          bill_id: p_bill_id,
          message: 'Fewer than 2 versions. Nothing to diff.',
          comparisons_computed: 0,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Sort by stage order, then by timestamp within same stage
    // (handles multiple committee revisions, etc.)
    const sorted = (versions as BillVersion[]).sort((a, b) => {
      const stageDiff =
        (STAGE_ORDER[a.stage] ?? 99) - (STAGE_ORDER[b.stage] ?? 99);
      if (stageDiff !== 0) return stageDiff;
      return (
        new Date(a.version_timestamp).getTime() -
        new Date(b.version_timestamp).getTime()
      );
    });

    // ── Clear spending anomalies ONCE before processing ──
    // Anomalies are recomputed, not append-only. Delete upfront so
    // the loop can insert freely without prior-iteration wipeout.
    await supabase
      .from('spending_anomalies')
      .delete()
      .eq('bill_id', p_bill_id)
      .catch(() => {});

    // ── Process each adjacent pair ──
    const comparisons: any[] = [];
    const allDiffs: any[] = [];
    let totalComparisons = 0;
    let totalDiffs = 0;

    for (let i = 0; i < sorted.length - 1; i++) {
      const fromVersion = sorted[i];
      const toVersion = sorted[i + 1];

      // Check if comparison already exists AND has diffs (partial-write recovery).
      // If comparison row exists but zero diffs were written (prior crash), re-process.
      const { data: existing } = await supabase
        .from('version_comparisons')
        .select('comparison_id')
        .eq('from_version_id', fromVersion.version_id)
        .eq('to_version_id', toVersion.version_id)
        .single();

      if (existing) {
        // Verify diffs actually exist for this comparison
        const { count: diffCount } = await supabase
          .from('mutation_diffs')
          .select('diff_id', { count: 'exact', head: true })
          .eq('comparison_id', existing.comparison_id);

        if (diffCount && diffCount > 0) {
          // Fully computed, skip
          continue;
        }
        // Partial write: comparison exists but no diffs. Fall through to re-process.
        // Delete the orphaned comparison row so upsert works cleanly.
        await supabase
          .from('version_comparisons')
          .delete()
          .eq('comparison_id', existing.comparison_id);
      }

      // ── Match provisions between versions ──
      const fromProvisions = Array.isArray(fromVersion.provisions_text)
        ? fromVersion.provisions_text
        : [];
      const toProvisions = Array.isArray(toVersion.provisions_text)
        ? toVersion.provisions_text
        : [];

      const matches = matchProvisions(fromProvisions, toProvisions);

      // ── Compute magnitude for modified provisions ──
      const modifiedMatches = matches.filter((m) => m.type === 'modified');
      if (modifiedMatches.length > 0) {
        // Batch embed all old + new texts
        const textsToEmbed: string[] = [];
        const textIndexMap: { matchIndex: number; side: 'old' | 'new' }[] = [];

        for (let mi = 0; mi < modifiedMatches.length; mi++) {
          const m = modifiedMatches[mi];
          if (m.old_text) {
            textsToEmbed.push(safeSlice(m.old_text, 8000));
            textIndexMap.push({ matchIndex: mi, side: 'old' });
          }
          if (m.new_text) {
            textsToEmbed.push(safeSlice(m.new_text, 8000));
            textIndexMap.push({ matchIndex: mi, side: 'new' });
          }
        }

        if (textsToEmbed.length > 0) {
          const embeddings = await batchEmbed(textsToEmbed);
          totalEmbeddingTokens += embeddings.tokenCount;

          // Reconstruct old/new embeddings per match
          const embeddingMap: Map<
            number,
            { old?: number[]; new?: number[] }
          > = new Map();

          for (let ei = 0; ei < textIndexMap.length; ei++) {
            const { matchIndex, side } = textIndexMap[ei];
            if (!embeddingMap.has(matchIndex)) {
              embeddingMap.set(matchIndex, {});
            }
            embeddingMap.get(matchIndex)![side] = embeddings.vectors[ei];
          }

          // Compute cosine distance for each modified match
          for (let mi = 0; mi < modifiedMatches.length; mi++) {
            const pair = embeddingMap.get(mi);
            if (pair?.old && pair?.new) {
              modifiedMatches[mi].magnitude = cosineDistance(
                pair.old,
                pair.new
              );
            } else {
              // Embedding failed for this pair. Treat as entirely new (worst-case)
              // rather than silently assuming moderate change.
              console.warn(
                `Embedding missing for provision "${modifiedMatches[mi].provision_title}". Defaulting magnitude to 1.0.`
              );
              modifiedMatches[mi].magnitude = 1.0;
            }
          }
        }
      }

      // ── Look up spending crossover ──
      const { data: fromSpending } = await supabase
        .from('spending_data')
        .select('spending_id, provision_index, provision_title, amount, category')
        .eq('version_id', fromVersion.version_id);

      const { data: toSpending } = await supabase
        .from('spending_data')
        .select('spending_id, provision_index, provision_title, amount, category')
        .eq('version_id', toVersion.version_id);

      const fromSpendingMap = buildSpendingMap(fromSpending || []);
      const toSpendingMap = buildSpendingMap(toSpending || []);

      // Populate spending crossover on diffs
      for (const match of matches) {
        const oldSpend = fromSpendingMap.get(match.provision_title);
        const newSpend = toSpendingMap.get(match.provision_title);

        if (match.type === 'added' && newSpend) {
          match.spending_delta = newSpend;
          match.old_spending = null;
          match.new_spending = newSpend;
        } else if (match.type === 'removed' && oldSpend) {
          match.spending_delta = -oldSpend;
          match.old_spending = oldSpend;
          match.new_spending = null;
        } else if (match.type === 'modified' && (oldSpend || newSpend)) {
          match.old_spending = oldSpend || null;
          match.new_spending = newSpend || null;
          if (oldSpend !== undefined && newSpend !== undefined) {
            match.spending_delta = newSpend - oldSpend;
          }
        }

        // Note: spending_data.has_mutation_crossover is set at INSERT time
        // by PM-MT.2. The canonical crossover signal is
        // mutation_diffs.spending_delta IS NOT NULL.
      }

      // ── Compute aggregate stats ──
      const provisionsAdded = matches.filter((m) => m.type === 'added').length;
      const provisionsRemoved = matches.filter((m) => m.type === 'removed').length;
      const provisionsModified = matches.filter((m) => m.type === 'modified').length;
      const totalProvisions = Math.max(fromProvisions.length, toProvisions.length);

      // Aggregate mutation = weighted sum of all magnitudes / total provisions.
      // Added + removed = 1.0 each. Modified = their cosine distance.
      // This weights breadth of change: a bill that rewrites everything moderately
      // (~0.3 each) scores higher than one that adds a single new section (1.0/50).
      const totalMagnitude = matches.reduce((sum, m) => sum + m.magnitude, 0);
      const aggregateMutation =
        totalProvisions > 0
          ? Math.min(totalMagnitude / totalProvisions, 1.0)
          : 0.0;

      // ── Write version_comparisons ──
      const { data: compData, error: compErr } = await supabase
        .from('version_comparisons')
        .upsert(
          {
            bill_id: p_bill_id,
            from_version_id: fromVersion.version_id,
            to_version_id: toVersion.version_id,
            aggregate_mutation: Math.round(aggregateMutation * 10000) / 10000,
            provisions_added: provisionsAdded,
            provisions_removed: provisionsRemoved,
            provisions_modified: provisionsModified,
            total_provisions: totalProvisions,
          },
          {
            onConflict: 'from_version_id,to_version_id',
            ignoreDuplicates: true,
          }
        )
        .select('comparison_id')
        .single();

      if (compErr) {
        console.error(`Comparison insert failed: ${compErr.message}`);
        continue;
      }

      const comparisonId = compData?.comparison_id;
      totalComparisons++;

      // ── Write mutation_diffs ──
      if (comparisonId && matches.length > 0) {
        const diffRows = matches.map((m) => ({
          comparison_id: comparisonId,
          bill_id: p_bill_id,
          provision_title: safeSlice(m.provision_title, 500),
          provision_index: m.provision_index,
          diff_type: m.type,
          magnitude: Math.round(m.magnitude * 10000) / 10000,
          category: m.category,
          old_text: m.old_text ? safeSlice(m.old_text, 5000) : null,
          new_text: m.new_text ? safeSlice(m.new_text, 5000) : null,
          spending_delta: m.spending_delta,
          old_spending: m.old_spending,
          new_spending: m.new_spending,
        }));

        const { error: diffErr } = await supabase
          .from('mutation_diffs')
          .insert(diffRows);

        if (diffErr) {
          console.error(`Diffs insert failed: ${diffErr.message}`);
        } else {
          totalDiffs += diffRows.length;
        }
      }

      // ── Write spending_comparisons (if spending data exists for both versions) ──
      if (
        (fromSpending && fromSpending.length > 0) ||
        (toSpending && toSpending.length > 0)
      ) {
        const fromTotal = (fromSpending || []).reduce(
          (s, r) => s + (r.amount || 0),
          0
        );
        const toTotal = (toSpending || []).reduce(
          (s, r) => s + (r.amount || 0),
          0
        );

        // Count spending-specific changes
        const spendingAdded = matches.filter(
          (m) => m.type === 'added' && m.new_spending !== null
        ).length;
        const spendingRemoved = matches.filter(
          (m) => m.type === 'removed' && m.old_spending !== null
        ).length;
        const spendingChanged = matches.filter(
          (m) =>
            m.type === 'modified' &&
            m.spending_delta !== null &&
            m.spending_delta !== 0
        ).length;

        await supabase
          .from('spending_comparisons')
          .upsert(
            {
              bill_id: p_bill_id,
              from_version_id: fromVersion.version_id,
              to_version_id: toVersion.version_id,
              total_delta: toTotal - fromTotal,
              provisions_added: spendingAdded,
              provisions_removed: spendingRemoved,
              provisions_changed: spendingChanged,
            },
            {
              onConflict: 'from_version_id,to_version_id',
              ignoreDuplicates: true,
            }
          )
          .catch((e: Error) =>
            console.error(`Spending comparison insert failed: ${e.message}`)
          );

        // ── Detect spending anomalies ──
        // Anomaly detection: provision spending > 3x average for this bill
        // OR spending_delta > 100% of original amount (cross-version spike).
        //
        // Magnitude formula: (ratio - 1) / 10, clamped to [0, 1].
        // A provision at 3x average = magnitude 0.2 (mild).
        // A provision at 13x average = magnitude 1.0 (ceiling).
        // This logarithmic-like compression prevents outlier provisions from
        // dominating the anomaly list while still ranking severity.
        //
        // Cross-version spike magnitude: pctChange / 5, clamped to [0, 1].
        // A 100% increase = 0.2. A 500%+ increase = 1.0.
        if (toSpending && toSpending.length > 0) {
          const avgSpending = toTotal / toSpending.length;
          const anomalies: any[] = [];

          for (const sp of toSpending) {
            let reason: string | null = null;
            let magnitude = 0;

            if (sp.amount > avgSpending * 3) {
              reason = `Outsized: ${formatDollars(sp.amount)} vs avg ${formatDollars(avgSpending)}`;
              magnitude = Math.min((sp.amount / avgSpending - 1) / 10, 1.0);
            }

            // Check for cross-version spike
            const matchingDiff = matches.find(
              (m) =>
                m.provision_title === sp.provision_title &&
                m.spending_delta !== null &&
                m.old_spending !== null &&
                m.old_spending > 0
            );
            if (
              matchingDiff &&
              matchingDiff.spending_delta !== null &&
              matchingDiff.old_spending !== null &&
              matchingDiff.old_spending > 0
            ) {
              const pctChange = Math.abs(
                matchingDiff.spending_delta / matchingDiff.old_spending
              );
              if (pctChange > 1.0) {
                reason = `Cross-version spike: ${formatDollars(matchingDiff.old_spending!)} to ${formatDollars(matchingDiff.new_spending!)}`;
                magnitude = Math.min(pctChange / 5, 1.0);
              }
            }

            if (reason) {
              anomalies.push({
                bill_id: p_bill_id,
                provision_id_ref: sp.spending_id,
                reason: safeSlice(reason, 500),
                magnitude: Math.round(magnitude * 10000) / 10000,
                amount: sp.amount,
              });
            }
          }

          if (anomalies.length > 0) {
            await supabase
              .from('spending_anomalies')
              .insert(anomalies)
              .catch((e: Error) =>
                console.error(`Anomaly insert failed: ${e.message}`)
              );
          }
        }
      }

      comparisons.push({
        from_stage: fromVersion.stage,
        to_stage: toVersion.stage,
        aggregate_mutation: aggregateMutation,
        provisions_added: provisionsAdded,
        provisions_removed: provisionsRemoved,
        provisions_modified: provisionsModified,
        total_provisions: totalProvisions,
        diffs_count: matches.length,
      });
    }

    // ── Log cost ──
    const embeddingCost = totalEmbeddingTokens * 0.00000002; // text-embedding-3-small rate
    if (totalEmbeddingTokens > 0) {
      await supabase.from('cost_log').insert({
        operation: 'EMBEDDING',
        provider: 'OPENAI',
        model: OPENAI_EMBED_MODEL,
        endpoint: 'compute-bill-mutation',
        token_count: totalEmbeddingTokens,
        estimated_cost_usd: embeddingCost,
      });
    }

    // ── Log pipeline event ──
    await supabase.from('pipeline_events').insert({
      operation: 'COMPUTE_MUTATION',
      provider: 'OPENAI',
      model: OPENAI_EMBED_MODEL,
      endpoint: 'compute-bill-mutation',
      token_count: totalEmbeddingTokens,
      estimated_cost_usd: embeddingCost,
    });

    const elapsed = Date.now() - startTime;

    return new Response(
      JSON.stringify({
        bill_id: p_bill_id,
        versions_count: sorted.length,
        comparisons_computed: totalComparisons,
        diffs_computed: totalDiffs,
        embedding_tokens: totalEmbeddingTokens,
        embedding_cost: embeddingCost,
        elapsed_ms: elapsed,
        comparisons,
      }),
      {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    );
  } catch (err) {
    const elapsed = Date.now() - startTime;
    const errorMessage = err instanceof Error ? err.message : 'Unknown error';

    await supabase
      .from('pipeline_events')
      .insert({
        operation: 'COMPUTE_MUTATION',
        provider: 'OPENAI',
        model: OPENAI_EMBED_MODEL,
        endpoint: 'compute-bill-mutation',
        token_count: totalEmbeddingTokens,
        estimated_cost_usd: 0,
        error_message: errorMessage.substring(0, 500),
      })
      .catch(() => {});

    return new Response(
      JSON.stringify({ error: errorMessage, elapsed_ms: elapsed }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    );
  }
});

// ═══════════════════════════════════════════════════════════
// PROVISION MATCHING
// ═══════════════════════════════════════════════════════════

/**
 * Match provisions between two versions using title similarity.
 *
 * Strategy:
 * 1. Exact title match (normalized) = "modified" (compare descriptions)
 * 2. Fuzzy title match (>FUZZY_MATCH_THRESHOLD Jaccard) = "modified"
 * 3. Remaining in toVersion only = "added"
 * 4. Remaining in fromVersion only = "removed"
 *
 * This is provision-level structural diff, not word-level text diff.
 * The magnitude score captures HOW MUCH the provision changed, not WHERE.
 */
function matchProvisions(
  fromProvisions: Provision[],
  toProvisions: Provision[]
): ProvisionMatch[] {
  const matches: ProvisionMatch[] = [];
  const matchedFrom = new Set<number>();
  const matchedTo = new Set<number>();

  // Pass 1: exact title match
  for (let ti = 0; ti < toProvisions.length; ti++) {
    for (let fi = 0; fi < fromProvisions.length; fi++) {
      if (matchedFrom.has(fi) || matchedTo.has(ti)) continue;
      if (
        normalizeTitle(toProvisions[ti].title) ===
        normalizeTitle(fromProvisions[fi].title)
      ) {
        matchedFrom.add(fi);
        matchedTo.add(ti);
        matches.push({
          type: 'modified',
          provision_index: ti,
          provision_title: toProvisions[ti].title,
          category: toProvisions[ti].category || fromProvisions[fi].category,
          old_text: buildProvisionText(fromProvisions[fi]),
          new_text: buildProvisionText(toProvisions[ti]),
          magnitude: 0, // Computed later via embeddings
          spending_delta: null,
          old_spending: null,
          new_spending: null,
        });
        break;
      }
    }
  }

  // Pass 2: fuzzy title match (Jaccard similarity on word tokens)
  for (let ti = 0; ti < toProvisions.length; ti++) {
    if (matchedTo.has(ti)) continue;
    let bestFi = -1;
    let bestScore = 0;

    for (let fi = 0; fi < fromProvisions.length; fi++) {
      if (matchedFrom.has(fi)) continue;
      const score = jaccardSimilarity(
        normalizeTitle(fromProvisions[fi].title),
        normalizeTitle(toProvisions[ti].title)
      );
      if (score > FUZZY_MATCH_THRESHOLD && score > bestScore) {
        bestScore = score;
        bestFi = fi;
      }
    }

    if (bestFi >= 0) {
      console.log(
        `Fuzzy match: "${fromProvisions[bestFi].title}" → "${toProvisions[ti].title}" (score: ${bestScore.toFixed(3)})`
      );
      matchedFrom.add(bestFi);
      matchedTo.add(ti);
      matches.push({
        type: 'modified',
        provision_index: ti,
        provision_title: toProvisions[ti].title,
        category:
          toProvisions[ti].category || fromProvisions[bestFi].category,
        old_text: buildProvisionText(fromProvisions[bestFi]),
        new_text: buildProvisionText(toProvisions[ti]),
        magnitude: 0,
        spending_delta: null,
        old_spending: null,
        new_spending: null,
      });
    }
  }

  // Pass 3: unmatched in toVersion = added
  for (let ti = 0; ti < toProvisions.length; ti++) {
    if (matchedTo.has(ti)) continue;
    matches.push({
      type: 'added',
      provision_index: ti,
      provision_title: toProvisions[ti].title,
      category: toProvisions[ti].category,
      old_text: null,
      new_text: buildProvisionText(toProvisions[ti]),
      magnitude: 1.0, // Entirely new
      spending_delta: null,
      old_spending: null,
      new_spending: null,
    });
  }

  // Pass 4: unmatched in fromVersion = removed
  for (let fi = 0; fi < fromProvisions.length; fi++) {
    if (matchedFrom.has(fi)) continue;
    matches.push({
      type: 'removed',
      provision_index: fi,
      provision_title: fromProvisions[fi].title,
      category: fromProvisions[fi].category,
      old_text: buildProvisionText(fromProvisions[fi]),
      new_text: null,
      magnitude: 1.0, // Entirely gone
      spending_delta: null,
      old_spending: null,
      new_spending: null,
    });
  }

  return matches;
}

function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function buildProvisionText(p: Provision): string {
  return safeSlice(`${p.title}. ${p.description}`, 8000);
}

/**
 * Jaccard similarity between two strings (word-level).
 * Returns 0.0 (no overlap) to 1.0 (identical word sets).
 */
function jaccardSimilarity(a: string, b: string): number {
  if (!a || !b) return 0;
  const setA = new Set(a.split(' '));
  const setB = new Set(b.split(' '));
  const intersection = new Set([...setA].filter((x) => setB.has(x)));
  const union = new Set([...setA, ...setB]);
  return union.size > 0 ? intersection.size / union.size : 0;
}

// ═══════════════════════════════════════════════════════════
// TEXT UTILITIES
// ═══════════════════════════════════════════════════════════

/**
 * Unicode-safe string truncation. Slices by code point, not UTF-16 code unit,
 * preventing severed surrogate pairs (emoji, math symbols, CJK extensions).
 */
function safeSlice(text: string, maxCodePoints: number): string {
  const codePoints = Array.from(text);
  if (codePoints.length <= maxCodePoints) return text;
  return codePoints.slice(0, maxCodePoints).join('');
}

// ═══════════════════════════════════════════════════════════
// EMBEDDINGS (transient, compute-and-discard)
// ═══════════════════════════════════════════════════════════

async function batchEmbed(
  texts: string[]
): Promise<{ vectors: number[][]; tokenCount: number }> {
  // OpenAI batch embedding: up to 2048 inputs per call.
  // For bills, rarely more than ~200 provisions across all versions.
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: OPENAI_EMBED_MODEL,
      input: texts,
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`OpenAI embedding error ${response.status}: ${errText}`);
  }

  const data = await response.json();
  const vectors: number[][] = data.data
    .sort((a: any, b: any) => a.index - b.index)
    .map((d: any) => d.embedding);
  const tokenCount = data.usage?.total_tokens || 0;

  return { vectors, tokenCount };
}

/**
 * Cosine distance between two vectors.
 * Returns 0.0 (identical) to 1.0 (orthogonal/opposite).
 * This is 1 - cosine_similarity.
 *
 * Note: OpenAI text-embedding-3-small returns pre-normalized vectors
 * (magnitude ~1.0), so the denominator is effectively 1.0 in practice.
 * We keep the full formula for correctness against unexpected API drift.
 */
function cosineDistance(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 1.0;

  let dotProduct = 0;
  let normA = 0;
  let normB = 0;

  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  const denominator = Math.sqrt(normA) * Math.sqrt(normB);
  if (denominator === 0) return 1.0;

  const similarity = dotProduct / denominator;
  // Clamp to [0, 1] range (floating point can produce tiny negatives)
  return Math.max(0, Math.min(1, 1 - similarity));
}

// ═══════════════════════════════════════════════════════════
// SPENDING HELPERS
// ═══════════════════════════════════════════════════════════

function buildSpendingMap(rows: SpendingRow[]): Map<string, number> {
  const map = new Map<string, number>();
  for (const row of rows) {
    map.set(row.provision_title, row.amount);
  }
  return map;
}

function formatDollars(amount: number): string {
  if (amount >= 1e12) return `$${(amount / 1e12).toFixed(1)}T`;
  if (amount >= 1e9) return `$${(amount / 1e9).toFixed(1)}B`;
  if (amount >= 1e6) return `$${(amount / 1e6).toFixed(1)}M`;
  if (amount >= 1e3) return `$${(amount / 1e3).toFixed(0)}K`;
  return `$${amount.toFixed(0)}`;
}
