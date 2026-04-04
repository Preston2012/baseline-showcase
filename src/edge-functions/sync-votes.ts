// ========================================================================
// sync-votes -- Scheduled Vote Ingestion Edge Function
//
// Fetches recent US Congress roll-call votes, parses member positions
// from House/Senate XML sources, maps to Baseline figures via bioguide_id,
// and batch-inserts via insert_votes_batch RPC.
//
// Triggered by pg_cron (every 2 hours).
// Auth: service_role JWT.
// ========================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { DOMParser } from "https://deno.land/x/deno_dom@v0.1.38/deno-dom-wasm.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const CONGRESS_API_KEY = Deno.env.get("CONGRESS_GOV_API_KEY") || Deno.env.get("CONGRESS_API_KEY") || "";
const LOOKBACK_DAYS = 7;
const CONGRESS = 119;
const SESSION = 1;

function log(msg: string) { console.log(`[sync-votes] ${msg}`); }

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

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }

  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace("Bearer ", "");
  if (!isServiceRole(token) && token !== SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    // ── 1. Check feature flag ─────────────────────────────────
    const { data: flag } = await supabase
      .from("feature_flags")
      .select("enabled")
      .eq("flag_name", "ENABLE_VOTE_TRACKING")
      .single();

    if (!flag?.enabled) {
      log("ENABLE_VOTE_TRACKING disabled - skipping");
      return json({ skipped: true, reason: "flag_disabled" });
    }

    // ── 2. Get figures with bioguide_id ───────────────────────
    const { data: figures, error: figErr } = await supabase
      .from("figures")
      .select("figure_id, name, metadata")
      .not("metadata->bioguide_id", "is", null);

    if (figErr || !figures?.length) {
      log(`No figures with bioguide_id: ${figErr?.message || "empty"}`);
      return json({ skipped: true, reason: "no_trackable_figures" });
    }

    const bioguideMap = new Map<string, string>();
    const nameMap = new Map<string, string>(); // LAST_NAME → figure_id (for Senate fallback)
    for (const fig of figures) {
      const bid = fig.metadata?.bioguide_id;
      if (bid) {
        bioguideMap.set(bid.toUpperCase(), fig.figure_id);
        // Extract last name for Senate matching
        const nameParts = (fig.name || "").split(" ");
        const lastName = nameParts[nameParts.length - 1].toUpperCase();
        if (lastName) nameMap.set(lastName, fig.figure_id);
      }
    }
    log(`Tracking ${bioguideMap.size} figures`);

    // ── 3. Date range ─────────────────────────────────────────
    const now = new Date();
    const from = new Date(now.getTime() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000);
    const fromStr = from.toISOString().split("T")[0];
    const toStr = now.toISOString().split("T")[0];

    let totalInserted = 0;
    const errors: string[] = [];

    // ── 4. House votes ────────────────────────────────────────
    try {
      const n = await fetchHouseVotes(fromStr, toStr, bioguideMap, supabase);
      totalInserted += n;
      log(`House: ${n} votes inserted`);
    } catch (e) {
      errors.push(`House: ${e}`);
      log(`House error: ${e}`);
    }

    // ── 5. Senate votes ───────────────────────────────────────
    try {
      const n = await fetchSenateVotes(fromStr, toStr, bioguideMap, nameMap, supabase);
      totalInserted += n;
      log(`Senate: ${n} votes inserted`);
    } catch (e) {
      errors.push(`Senate: ${e}`);
      log(`Senate error: ${e}`);
    }

    // ── 6. Log pipeline event ─────────────────────────────────
    await supabase.from("pipeline_events").insert({
      stage: "VOTE_INGESTION",
      event_type: errors.length > 0 ? "PARTIAL" : "SUCCESS",
      details: { totalInserted, errors, dateRange: `${fromStr} to ${toStr}` },
    });

    return json({ success: true, totalInserted, errors, dateRange: `${fromStr} to ${toStr}` });

  } catch (err) {
    log(`Fatal: ${err}`);
    await supabase.from("pipeline_events").insert({
      stage: "VOTE_INGESTION",
      event_type: "ERROR",
      details: { error: String(err) },
    }).catch(() => {});
    return json({ error: String(err) }, 500);
  }
});

// ── House Votes ─────────────────────────────────────────────────
async function fetchHouseVotes(
  fromStr: string,
  toStr: string,
  bioguideMap: Map<string, string>,
  supabase: ReturnType<typeof createClient>,
): Promise<number> {
  // Congress.gov API returns houseRollCallVotes
  const listUrl = `https://api.congress.gov/v3/house-vote?api_key=${CONGRESS_API_KEY}&fromDateTime=${fromStr}T00:00:00Z&toDateTime=${toStr}T23:59:59Z&limit=50&format=json`;

  const listResp = await fetch(listUrl, { signal: AbortSignal.timeout(15000) });
  if (!listResp.ok) throw new Error(`API ${listResp.status}`);

  const listData = await listResp.json();
  const rollCalls = listData.houseRollCallVotes || listData.votes || [];
  log(`House: ${rollCalls.length} roll calls found`);

  let inserted = 0;

  for (const rc of rollCalls) {
    try {
      const rollNumber = rc.rollCallNumber || rc.rollNumber;
      const congress = rc.congress || CONGRESS;
      const startDate = rc.startDate || rc.date || toStr;
      const voteDate = startDate.split("T")[0];

      if (!rollNumber) continue;

      // Extract year from vote date for clerk URL
      const voteYear = voteDate.split("-")[0] || new Date().getFullYear().toString();
      const paddedRoll = String(rollNumber).padStart(3, "0");
      const xmlUrl = `https://clerk.house.gov/evs/${voteYear}/roll${paddedRoll}.xml`;

      const xmlResp = await fetch(xmlUrl, { signal: AbortSignal.timeout(10000) });
      if (!xmlResp.ok) {
        log(`House roll ${rollNumber}: XML ${xmlResp.status}`);
        continue;
      }

      const xmlText = await xmlResp.text();
      const doc = new DOMParser().parseFromString(xmlText, "text/html");
      if (!doc) continue;

      const legisNum = doc.querySelector("legis-num")?.textContent?.trim() || "";
      const billId = legisNum
        ? normalizeBillId(legisNum, congress, "HOUSE")
        : `ROLL-HOUSE-${congress}-${rollNumber}`;
      const question = doc.querySelector("vote-question")?.textContent?.trim() || "";
      const result = doc.querySelector("vote-result")?.textContent?.trim() || "";

      const voters = doc.querySelectorAll("recorded-vote");
      const batch: VoteRecord[] = [];

      for (const voter of voters) {
        const legislator = voter.querySelector("legislator");
        if (!legislator) continue;

        const bioId = legislator.getAttribute("name-id")?.toUpperCase();
        if (!bioId) continue;

        const figureId = bioguideMap.get(bioId);
        if (!figureId) continue;

        const voteText = voter.querySelector("vote")?.textContent?.trim() || "";
        batch.push({
          figure_id: figureId,
          bill_id: billId,
          vote_date: voteDate,
          chamber: "HOUSE",
          position: mapPosition(voteText),
          congress_session: congress,
          roll_call_number: rollNumber,
          question,
          result,
        });
      }

      if (batch.length > 0) {
        const { data: n } = await supabase.rpc("insert_votes_batch", { p_votes: batch });
        inserted += typeof n === "number" ? n : batch.length;
      }

      await delay(250);
    } catch (e) {
      log(`House roll ${rc.rollCallNumber}: ${e}`);
    }
  }

  return inserted;
}

// ── Senate Votes ────────────────────────────────────────────────
// Senate has no Congress.gov listing API. We scrape the XML vote menu
// from senate.gov to get recent roll call numbers, then fetch each.
async function fetchSenateVotes(
  fromStr: string,
  _toStr: string,
  bioguideMap: Map<string, string>,
  nameMap: Map<string, string>,
  supabase: ReturnType<typeof createClient>,
): Promise<number> {
  // Get the vote listing XML
  const menuUrl = `https://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_${CONGRESS}_${SESSION}.xml`;
  const menuResp = await fetch(menuUrl, { signal: AbortSignal.timeout(15000) });
  if (!menuResp.ok) {
    log(`Senate vote menu ${menuResp.status} - skipping Senate`);
    return 0;
  }

  const menuXml = await menuResp.text();
  const menuDoc = new DOMParser().parseFromString(menuXml, "text/html");
  if (!menuDoc) return 0;

  // Parse vote entries from menu XML
  const voteEntries = menuDoc.querySelectorAll("vote");
  const fromDate = new Date(fromStr);
  const recentVotes: { rollNumber: number; date: string }[] = [];

  for (const entry of voteEntries) {
    const voteNum = entry.querySelector("vote_number")?.textContent?.trim();
    const dateStr = entry.querySelector("vote_date")?.textContent?.trim();

    if (!voteNum || !dateStr) continue;

    // Parse date - format varies: "Month DD, YYYY" or similar
    const voteDate = parseSenateDate(dateStr);
    if (!voteDate || voteDate < fromDate) continue;

    recentVotes.push({
      rollNumber: parseInt(voteNum, 10),
      date: voteDate.toISOString().split("T")[0],
    });
  }

  log(`Senate: ${recentVotes.length} recent votes in menu`);
  let inserted = 0;

  for (const rv of recentVotes) {
    try {
      const paddedRoll = String(rv.rollNumber).padStart(5, "0");
      const xmlUrl = `https://www.senate.gov/legislative/LIS/roll_call_votes/vote${CONGRESS}${SESSION}/vote_${CONGRESS}_${SESSION}_${paddedRoll}.xml`;

      const xmlResp = await fetch(xmlUrl, { signal: AbortSignal.timeout(10000) });
      if (!xmlResp.ok) continue;

      const xmlText = await xmlResp.text();
      const doc = new DOMParser().parseFromString(xmlText, "text/html");
      if (!doc) continue;

      const question = doc.querySelector("vote_question_text")?.textContent?.trim() || "";
      const result = doc.querySelector("vote_result_text")?.textContent?.trim() || "";
      const issueNum = doc.querySelector("issue num")?.textContent?.trim() || "";
      const billId = issueNum
        ? normalizeBillId(issueNum, CONGRESS, "SENATE")
        : `ROLL-SENATE-${CONGRESS}-${rv.rollNumber}`;

      const members = doc.querySelectorAll("member");
      const batch: VoteRecord[] = [];

      for (const member of members) {
        const lastName = member.querySelector("last_name")?.textContent?.trim()?.toUpperCase();
        const voteText = member.querySelector("vote_cast")?.textContent?.trim() || "";

        if (!lastName) continue;

        // Match by last name (Senate XML doesn't reliably have bioguide_id)
        const figureId = nameMap.get(lastName);
        if (!figureId) continue;

        batch.push({
          figure_id: figureId,
          bill_id: billId,
          vote_date: rv.date,
          chamber: "SENATE",
          position: mapPosition(voteText),
          congress_session: CONGRESS,
          roll_call_number: rv.rollNumber,
          question,
          result,
        });
      }

      if (batch.length > 0) {
        const { data: n } = await supabase.rpc("insert_votes_batch", { p_votes: batch });
        inserted += typeof n === "number" ? n : batch.length;
      }

      await delay(300);
    } catch (e) {
      log(`Senate roll ${rv.rollNumber}: ${e}`);
    }
  }

  return inserted;
}

// ── Helpers ─────────────────────────────────────────────────────

interface VoteRecord {
  figure_id: string;
  bill_id: string;
  vote_date: string;
  chamber: string;
  position: string;
  congress_session: number;
  roll_call_number: number;
  question: string;
  result: string;
}

function mapPosition(raw: string): string {
  const u = raw.toUpperCase().trim();
  if (u === "YEA" || u === "AYE" || u === "YES") return "YEA";
  if (u === "NAY" || u === "NO") return "NAY";
  if (u === "PRESENT") return "PRESENT";
  return "NOT_VOTING";
}

function normalizeBillId(legisNum: string, congress: number, _chamber: string): string {
  const c = legisNum.replace(/\./g, "").replace(/\s+/g, " ").trim().toUpperCase();

  const patterns: [RegExp, string][] = [
    [/^H\s*R\s*(\d+)/, "HR"],
    [/^S\s*(\d+)$/, "S"],
    [/^H\s*J\s*RES\s*(\d+)/, "HJRES"],
    [/^S\s*J\s*RES\s*(\d+)/, "SJRES"],
    [/^H\s*CON\s*RES\s*(\d+)/, "HCONRES"],
    [/^S\s*CON\s*RES\s*(\d+)/, "SCONRES"],
    [/^H\s*RES\s*(\d+)/, "HRES"],
    [/^S\s*RES\s*(\d+)/, "SRES"],
  ];

  for (const [regex, prefix] of patterns) {
    const match = c.match(regex);
    if (match) return `${prefix}-${match[1]}-${congress}`;
  }

  return `ROLL-${_chamber}-${congress}-${c.replace(/\s+/g, "-")}`;
}

function parseSenateDate(dateStr: string): Date | null {
  try {
    // Try standard formats
    const d = new Date(dateStr);
    if (!isNaN(d.getTime())) return d;

    // Try "DD-Mon-YYYY" format (e.g., "06-Mar-2026")
    const parts = dateStr.match(/(\d{1,2})-(\w{3})-(\d{4})/);
    if (parts) {
      return new Date(`${parts[2]} ${parts[1]}, ${parts[3]}`);
    }

    return null;
  } catch {
    return null;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
