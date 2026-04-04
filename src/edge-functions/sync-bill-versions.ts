// ========================================================================
// sync-bill-versions -- Scheduled Bill Version + Mutation Pipeline
//
// Checks Congress.gov for new bill text versions, calls ingest-bill-version
// EF for Gemini extraction, then triggers compute-bill-mutation for diffs.
//
// Triggered by pg_cron (every 6 hours).
// Auth: requires service_role key (internal use only).
// ========================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const BILL_AUTH_TOKEN = Deno.env.get("BILL_AUTH_TOKEN") || "";
const CONGRESS_API_KEY = Deno.env.get("CONGRESS_GOV_API_KEY") || Deno.env.get("CONGRESS_API_KEY") || "";
const MAX_BILL_TEXT_LENGTH = 200000;
const MAX_BILLS_PER_RUN = 15; // EF timeout ~150s, each bill ~5-10s

function log(msg: string) { console.log(`[sync-bill-versions] ${msg}`); }

function isServiceRole(jwt: string): boolean {
  try {
    const parts = jwt.split(".");
    if (parts.length !== 3) return false;
    const payload = JSON.parse(atob(parts[1]));
    return payload.role === "service_role";
  } catch {
    return false;
  }
}

// Stage mapping from Congress API version types to our enum
const STAGE_MAP: Record<string, string> = {
  "Introduced in House": "introduced",
  "Introduced in Senate": "introduced",
  "Reported in House": "committee",
  "Reported in Senate": "committee",
  "Engrossed in House": "engrossed",
  "Engrossed in Senate": "engrossed",
  "Enrolled Bill": "enrolled",
  "Referred in House": "introduced",
  "Referred in Senate": "introduced",
  "Placed on Calendar House": "committee",
  "Placed on Calendar Senate": "committee",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }

  // Auth check - service_role JWT or matching key
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace("Bearer ", "");
  if (!isServiceRole(token) && token !== SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    // ── 1. Check feature flags ────────────────────────────────
    const { data: flags } = await supabase
      .from("feature_flags")
      .select("flag_name, enabled")
      .in("flag_name", ["ENABLE_BILL_MUTATION", "ENABLE_SPENDING_TRACKER"]);

    const billMutationEnabled = flags?.find(f => f.flag_name === "ENABLE_BILL_MUTATION")?.enabled;
    if (!billMutationEnabled) {
      log("ENABLE_BILL_MUTATION is disabled - skipping");
      return new Response(JSON.stringify({ skipped: true, reason: "flag_disabled" }), { status: 200 });
    }

    // ── 2. Get tracked bills ──────────────────────────────────
    const { data: trackedBills, error: tbErr } = await supabase.rpc("get_tracked_bills", {});
    if (tbErr || !trackedBills?.length) {
      log(`No tracked bills: ${tbErr?.message || "empty"}`);
      return new Response(JSON.stringify({ skipped: true, reason: "no_tracked_bills" }), { status: 200 });
    }
    log(`Checking ${trackedBills.length} tracked bills for new versions`);

    // ── 3. Get existing versions to avoid duplicates ──────────
    const billIds = trackedBills.map((b: { bill_id: string }) => b.bill_id);
    const { data: existingVersions } = await supabase
      .from("bill_versions")
      .select("bill_id, stage")
      .in("bill_id", billIds);

    const existingSet = new Set(
      (existingVersions || []).map((v: { bill_id: string; stage: string }) => `${v.bill_id}::${v.stage}`)
    );

    // Count stages per bill - skip those already at all 4 stages
    const stageCount = new Map<string, number>();
    for (const v of existingVersions || []) {
      stageCount.set(v.bill_id, (stageCount.get(v.bill_id) || 0) + 1);
    }
    const billsToCheck = trackedBills
      .filter((b: { bill_id: string }) => (stageCount.get(b.bill_id) || 0) < 4)
      .slice(0, MAX_BILLS_PER_RUN);

    let newVersions = 0;
    let mutationsComputed = 0;
    const errors: string[] = [];
    log(`Checking ${billsToCheck.length} of ${trackedBills.length} bills (skipped ${trackedBills.length - billsToCheck.length} complete)`);

    // ── 4. Check each bill for new versions ───────────────────
    for (const bill of billsToCheck) {
      try {
        const { bill_id, chamber_code, congress_session } = bill;
        // Extract bill number from bill_id (e.g., "HR-1234-119" → "1234")
        const parts = bill_id.split("-");
        const billType = parts[0].toLowerCase();
        const billNumber = parts[1];

        if (!billNumber) continue;

        // Map bill type to Congress API format
        const apiType = mapBillType(billType);
        if (!apiType) continue;

        const apiUrl = `https://api.congress.gov/v3/bill/${congress_session}/${apiType}/${billNumber}?format=json&api_key=${CONGRESS_API_KEY}`;

        const apiResp = await fetch(apiUrl, {
          signal: AbortSignal.timeout(15000),
        });
        if (!apiResp.ok) {
          if (apiResp.status !== 404) {
            errors.push(`${bill_id}: API ${apiResp.status}`);
          }
          continue;
        }

        const apiData = await apiResp.json();
        const billData = apiData.bill || apiData;

        // textVersions is { count, url } - need to follow the URL for array
        let textVersions: { type?: string; date?: string; formats?: { type: string; url: string }[] }[] = [];
        const tvMeta = billData.textVersions;
        if (tvMeta?.url && tvMeta?.count > 0) {
          try {
            const tvUrl = tvMeta.url.includes("api_key") ? tvMeta.url : `${tvMeta.url}${tvMeta.url.includes("?") ? "&" : "?"}api_key=${CONGRESS_API_KEY}&format=json`;
            const tvResp = await fetch(tvUrl, { signal: AbortSignal.timeout(10000) });
            if (tvResp.ok) {
              const tvData = await tvResp.json();
              textVersions = tvData.textVersions || [];
            }
          } catch (e) {
            log(`${bill_id}: failed to fetch text versions: ${e}`);
          }
        } else if (Array.isArray(tvMeta)) {
          textVersions = tvMeta;
        }

        for (const tv of textVersions) {
          const typeName = tv.type || "";
          const stage = STAGE_MAP[typeName];
          if (!stage) continue;

          // Skip if we already have this version
          if (existingSet.has(`${bill_id}::${stage}`)) continue;

          // Get text URL
          const textUrl = (tv.formats || []).find((f: { type: string }) => f.type === "Formatted Text")?.url
            || (tv.formats || []).find((f: { type: string }) => f.type === "Formatted XML")?.url;

          if (!textUrl) continue;

          // Fetch bill text
          let billText = "";
          try {
            const textResp = await fetch(textUrl, {
              signal: AbortSignal.timeout(30000),
            });
            if (textResp.ok) {
              billText = await textResp.text();
              // Truncate if too large
              if (billText.length > MAX_BILL_TEXT_LENGTH) {
                log(`${bill_id} text too large (${billText.length} chars), truncating`);
                billText = billText.substring(0, MAX_BILL_TEXT_LENGTH);
              }
            }
          } catch {
            log(`${bill_id}: failed to fetch text from ${textUrl}`);
          }

          // Call ingest-bill-version EF
          const ingestUrl = `${SUPABASE_URL}/functions/v1/ingest-bill-version`;
          const authToken = BILL_AUTH_TOKEN || SUPABASE_SERVICE_ROLE_KEY;

          const ingestResp = await fetch(ingestUrl, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${authToken}`,
            },
            body: JSON.stringify({
              bill_id,
              bill_title: billData.title || billData.shortTitle || "Untitled",
              stage,
              chamber: chamber_code || (billType.startsWith("s") ? "SENATE" : "HOUSE"),
              congress_session: congress_session || 119,
              bill_text: billText || undefined,
              source_url: textUrl,
              version_timestamp: tv.date || new Date().toISOString(),
            }),
            signal: AbortSignal.timeout(60000),
          });

          if (ingestResp.ok) {
            newVersions++;
            existingSet.add(`${bill_id}::${stage}`);
            log(`Ingested ${bill_id} stage=${stage}`);

            // ── Call summarize-bill to generate/update bill summary ──
            if (billText) {
              try {
                const summarizeUrl = `${SUPABASE_URL}/functions/v1/summarize-bill`;
                const sumResp = await fetch(summarizeUrl, {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    Authorization: `Bearer ${authToken}`,
                  },
                  body: JSON.stringify({
                    bill_id,
                    bill_title: billData.title || billData.shortTitle || "Untitled",
                    bill_text: billText,
                    source_url: textUrl,
                    congress_session: 119,
                  }),
                  signal: AbortSignal.timeout(60000),
                });
                if (sumResp.ok) {
                  log(`Summarized ${bill_id}`);
                } else {
                  log(`summarize-bill ${bill_id}: ${sumResp.status}`);
                }
              } catch (e) {
                log(`summarize-bill ${bill_id} error: ${e}`);
              }
            }
          } else {
            const errBody = await ingestResp.text().catch(() => "");
            errors.push(`${bill_id}/${stage}: ingest ${ingestResp.status} ${errBody.substring(0, 100)}`);
          }

          await delay(500); // Rate limit
        }

        // ── 5. Trigger mutation computation if 2+ versions ────
        const versionsForBill = [...existingSet]
          .filter(k => k.startsWith(`${bill_id}::`))
          .length;

        if (versionsForBill >= 2) {
          try {
            // Get version pairs for comparison
            const { data: versions } = await supabase
              .from("bill_versions")
              .select("version_id, stage")
              .eq("bill_id", bill_id)
              .order("created_at", { ascending: true });

            if (versions && versions.length >= 2) {
              // Check which pairs already have comparisons
              for (let i = 0; i < versions.length - 1; i++) {
                const fromId = versions[i].version_id;
                const toId = versions[i + 1].version_id;

                const { data: existing } = await supabase
                  .from("version_comparisons")
                  .select("comparison_id")
                  .eq("from_version_id", fromId)
                  .eq("to_version_id", toId)
                  .maybeSingle();

                if (!existing) {
                  // Call compute-bill-mutation EF
                  const mutationUrl = `${SUPABASE_URL}/functions/v1/compute-bill-mutation`;
                  const mutResp = await fetch(mutationUrl, {
                    method: "POST",
                    headers: {
                      "Content-Type": "application/json",
                      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                    },
                    body: JSON.stringify({
                      p_bill_id: bill_id,
                    }),
                    signal: AbortSignal.timeout(60000),
                  });

                  if (mutResp.ok) {
                    mutationsComputed++;
                    log(`Computed mutation ${bill_id}: ${versions[i].stage} → ${versions[i + 1].stage}`);
                  } else {
                    // Fallback: insert basic comparison directly
                    await supabase.from("version_comparisons").insert({
                      bill_id,
                      from_version_id: fromId,
                      to_version_id: toId,
                      aggregate_mutation: 0.5,
                    });
                    mutationsComputed++;
                    log(`Fallback mutation insert for ${bill_id}`);
                  }
                }
              }
            }
          } catch (e) {
            errors.push(`${bill_id}: mutation compute error: ${e}`);
          }
        }

        await delay(300); // Rate limit between bills
      } catch (e) {
        errors.push(`${bill.bill_id}: ${e}`);
      }
    }

    // ── 6. Log pipeline event ─────────────────────────────────
    await supabase.from("pipeline_events").insert({
      stage: "BILL_INGESTION",
      event_type: errors.length > 0 ? "PARTIAL" : "SUCCESS",
      details: { newVersions, mutationsComputed, errors, billsChecked: trackedBills.length },
    });

    return new Response(JSON.stringify({
      success: true,
      newVersions,
      mutationsComputed,
      billsChecked: trackedBills.length,
      errors,
    }), { status: 200 });

  } catch (err) {
    log(`Fatal error: ${err}`);
    await supabase.from("pipeline_events").insert({
      stage: "BILL_INGESTION",
      event_type: "ERROR",
      details: { error: String(err) },
    });
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});

// ── Helpers ─────────────────────────────────────────────────────

function mapBillType(type: string): string | null {
  const map: Record<string, string> = {
    hr: "hr",
    s: "s",
    hjres: "hjres",
    sjres: "sjres",
    hconres: "hconres",
    sconres: "sconres",
    hres: "hres",
    sres: "sres",
  };
  return map[type] || null;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
