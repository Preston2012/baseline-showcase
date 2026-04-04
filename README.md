# Baseline: Political Intelligence Platform

Baseline is a political intelligence platform that tracks 106 public figures using 4 independent AI providers. Each statement is analyzed separately by Claude, GPT, Gemini, and Grok, then reconciled through a consensus engine that detects and flags model disagreements. Built solo using a documented multi-model orchestration methodology across 500+ build sessions.

[![Google Play](https://img.shields.io/badge/Google%20Play-Approved-green)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B)]()
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%2017-3ECF8E)]()

---

## What This Repo Contains

- Architecture documentation and system design ([SYSTEM_DESIGN.md](SYSTEM_DESIGN.md), [ARCHITECTURE.mermaid](ARCHITECTURE.mermaid))
- 10 Flutter screens with full UI logic ([src/flutter/screens/](src/flutter/screens/))
- 15 custom widgets including hand-painted icon sets, CustomPainter data visualizations, and animated components ([src/flutter/widgets/](src/flutter/widgets/))
- 9 data models with defensive JSON parsing, factory constructors, and null safety ([src/flutter/models/](src/flutter/models/))
- 5 service classes showing Supabase RPC integration patterns ([src/flutter/services/](src/flutter/services/))
- 2 state management providers ([src/flutter/providers/](src/flutter/providers/))
- All 22 Supabase Edge Functions: analysis pipeline, consensus engine, legislative tracking, feed API, subscription management ([src/edge-functions/](src/edge-functions/))
- 30 PostgreSQL migrations showing schema evolution from MVP to production ([src/sql/](src/sql/))
- App configuration: constants, routing, theme tokens ([src/config/](src/config/))

This is a public showcase representing the majority of the production codebase. Remaining private code is available for hiring review.

## What Is Intentionally Not Public

- AI prompt text sent to each provider (redacted in-place, control flow visible)
- Consensus scoring weights and threshold values (redacted as constants)
- 18 additional Flutter screens (settings, onboarding, auth, paywall)
- Production environment configuration (API keys, Supabase URLs)
- Trademarked icon assets

Contact [Droiddna2013@gmail.com](mailto:Droiddna2013@gmail.com) for private repo access.

---

## Why This Project Matters

Political discourse analysis is dominated by single-model tools with no bias correction. When one AI provider hallucinates or carries a political lean, there is no check on the output. Baseline's multi-provider consensus approach treats model disagreement as signal, not noise. Statements where providers fundamentally disagree are surfaced, not hidden.

---

## Architecture Overview

```
Official Sources
    |
    v
Ingestion Pipeline (Make.com workflows, source hashing, dedup)
    |
    v
Extraction (Gemini structured output)
    |
    v
Multi-Provider Analysis (Claude + GPT + Grok in parallel)
    |       |       |
    v       v       v
  [Each returns: repetition, novelty, affect, entropy, framing]
    |       |       |
    v       v       v
Consensus Engine (agreement measurement, variance detection, outlier flagging)
    |
    v
Scored Statement (signal rank, agreement level, framing consensus)
    |
    v
Feed / Profiles / Trends / Legislative Correlation
```

See [ARCHITECTURE.mermaid](ARCHITECTURE.mermaid) for the full component diagram.

---

## Key Technical Decisions

### Why 4 AI providers instead of 1 or 2

**Decision:** Route every statement to Claude, GPT, and Grok independently for analysis. Gemini handles structured extraction.

**Why:** Single models hallucinate, carry political bias, and degrade silently between versions. With 2 providers, a disagreement is a coin flip. With 3+ independent analyses, you can identify the outlier and measure confidence.

**What we observed:** GPT and Claude agreed on framing classification roughly 78% of the time. When they disagreed, Grok broke the tie in a consistent direction roughly 60% of the time, which was enough to flag genuinely ambiguous statements rather than forcing a binary call.

**Tradeoff:** 3x the API cost per statement. Cost tracking (11,224 log entries) revealed GPT-4 was roughly 10x more expensive per analysis than Gemini, which led to using Gemini for extraction (where structured output matters more than reasoning depth) and reserving GPT/Claude/Grok for analysis.

### Why Supabase Edge Functions over a traditional backend

**Decision:** 22 Deno Edge Functions deployed globally via Supabase.

**Why:** Serverless, TypeScript-native, globally distributed, scales to zero. No server management for a solo developer.

**Tradeoff:** Cold start latency on infrequently-called functions. No long-running processes, so the analysis pipeline is event-driven rather than streaming. Functions that need to orchestrate multiple steps (like the full ingestion pipeline) rely on Make.com workflows to chain calls.

### Why Flutter over React Native

**Decision:** Flutter 3.x with Dart.

**Why:** Dart's type safety caught schema mismatches at compile time during rapid iteration. Custom painting (CustomPainter) was essential for the consensus badge: 37 visual treatments based on agreement level, model count, and variance. React Native would have required a bridge to native canvas.

**Tradeoff:** Smaller ecosystem, fewer third-party packages. Hiring pool is smaller for Flutter than React Native.

### Why RLS on every table

**Decision:** Row Level Security enabled on all 30 tables, even for a solo developer.

**Why:** RLS pushes access control into PostgreSQL. Every query is filtered at the database level. There is no class of bug where a missing middleware check exposes data.

**Tradeoff:** Query complexity increases. Debugging RLS policy interactions is harder than debugging application-layer auth. Some queries required restructuring to work within RLS constraints.

### Why cost tracking per API call

**Decision:** Every AI API call logs to `cost_log` with provider, model, input/output tokens, and estimated USD.

**Why:** Without per-call cost tracking, budget overruns are invisible until the invoice arrives. Early logging revealed that GPT-4 was roughly 10x more expensive per analysis than Gemini. This data drove the decision to use Gemini for extraction and reserve expensive providers for analysis only.

**Tradeoff:** Additional write per API call. At 11,224 log entries, storage cost is negligible, but it adds latency to the analysis path (mitigated by logging asynchronously after the response is stored).

### Why 5-layer deduplication

**Decision:** Source hashing, content fingerprinting, ingestion-time dedup, statement-level dedup, and analysis-level dedup.

**Why:** Early versions ingested duplicates that corrupted consensus scores. A statement analyzed twice would double-count one provider's output, skewing the consensus. Each dedup layer catches a different failure mode: same URL re-crawled, same text from different sources, same statement re-triggered by automation, same analysis re-run after a partial failure.

**Tradeoff:** Pipeline complexity. Five dedup checks add latency to ingestion. But the cost of a false duplicate (missed statement) is lower than the cost of a false unique (corrupted consensus).

### Why consensus scoring instead of simple averaging

**Decision:** Compute inter-provider agreement, variance detection, outlier flagging, and framing consensus rather than averaging scores.

**Why:** Averaging hides disagreement. If Claude scores a statement at 80 and GPT scores it at 20, the average (50) tells you nothing. Variance detection surfaces these cases as high-signal: the providers fundamentally disagree about what the statement means, which is often more interesting than the cases where they agree.

**Tradeoff:** More complex data model (stddev columns, framing_split JSONB, variance_detected boolean). More complex frontend rendering (37 visual treatments in the consensus badge). But the alternative, a single number, would lose the most valuable signal in the system.

---

## Where to Look First

### Edge Functions (orchestration and pipeline)

| File | What it shows |
|------|--------------|
| [`analyze-statement.sample.ts`](src/edge-functions/analyze-statement.sample.ts) | Multi-provider routing: 4 providers called via Promise.allSettled, response normalization, cost logging. Prompt text redacted. |
| [`compute-consensus.sample.ts`](src/edge-functions/compute-consensus.sample.ts) | Consensus algorithm: per-metric averages/stddev, variance detection, outlier flagging, framing majority vote. Threshold values redacted. |
| [`get-feed.ts`](src/edge-functions/get-feed.ts) | Smart feed ranking: signal x recency_decay x variance_boost x novelty_boost, figure diversity cap, 5 sort modes. |
| [`get-narrative-sync.ts`](src/edge-functions/get-narrative-sync.ts) | 865-line narrative consistency engine. Measures how a figure's positions shift over time. |
| [`compute-bill-mutation.ts`](src/edge-functions/compute-bill-mutation.ts) | 857-line bill version differ. Tracks legislative changes between bill revisions. |
| [`summarize-bill.ts`](src/edge-functions/summarize-bill.ts) | AI-powered bill summarization with provision extraction and category classification. Prompt text redacted. |
| [`check-entitlement.ts`](src/edge-functions/check-entitlement.ts) | Rate limiting, feature gating, signed entitlement tokens with HMAC-SHA256. |
| [`revenuecat-webhook.ts`](src/edge-functions/revenuecat-webhook.ts) | Subscription lifecycle: idempotency, PII sanitization, constant-time auth, store mapping. |

### Flutter (screens, custom painters, data viz)

| File | What it shows |
|------|--------------|
| [`screens/figure_profile.dart`](src/flutter/screens/figure_profile.dart) | 3,900+ line figure profile with historical trends, framing radar, and signal timeline. |
| [`screens/today_feed.dart`](src/flutter/screens/today_feed.dart) | 3,200+ line main feed screen with smart ranking, pull-to-refresh, and infinite scroll. |
| [`screens/lens_lab.dart`](src/flutter/screens/lens_lab.dart) | 2,600+ line multi-model comparison view. Side-by-side provider analysis. |
| [`widgets/baseline_icons.dart`](src/flutter/widgets/baseline_icons.dart) | 1,200+ lines of hand-painted custom icons via CustomPainter. |
| [`widgets/convergence_painter.dart`](src/flutter/widgets/convergence_painter.dart) | 1,600+ line narrative convergence visualization. |
| [`widgets/framing_fingerprint.dart`](src/flutter/widgets/framing_fingerprint.dart) | 1,900+ line framing fingerprint data visualization. |
| [`widgets/constellation_nav.dart`](src/flutter/widgets/constellation_nav.dart) | 1,300+ line custom navigation system. |
| [`consensus_badge.dart`](src/flutter/consensus_badge.dart) | 1,100+ line CustomPainter with 37 visual treatments and animated ring gauge. |

### Data layer and infrastructure

| File | What it shows |
|------|--------------|
| [`models/`](src/flutter/models/) | 9 data models: analysis, bill_summary, consensus, feed_statement, figure, framing, lens_lab, trends, vote. |
| [`services/`](src/flutter/services/) | 5 service classes: Supabase RPC integration, error handling, response parsing. |
| [`providers/`](src/flutter/providers/) | State management for feed and figures. |
| [`utils/gate_state_machine.dart`](src/flutter/utils/gate_state_machine.dart) | Feature gating state machine for tier-based access control. |
| [`sql/`](src/sql/) | 30 PostgreSQL migrations: schema evolution from MVP to production, RLS policies, custom RPCs. |

---

## Representative Code Paths

### Path 1: Statement analysis and consensus

A statement enters the system. `analyze-statement.ts` validates the request, then calls Claude, GPT, Gemini, and Grok in parallel via `Promise.allSettled`. Each provider returns structured JSON (repetition, novelty, affective language rate, topic entropy, framing label). Responses are validated, clamped to 0-100 ranges, and normalized into a common schema. Each result is inserted into the `analyses` table with a mirror row in `analyses_audit`. Token usage and estimated USD cost are logged to `cost_log`. Then `compute-consensus.ts` loads all provider results, computes per-metric averages and standard deviations, measures inter-provider spread, detects variance (any metric stddev above threshold), identifies the outlier provider, determines framing consensus via majority vote, and upserts the result to the `consensus` table.

### Path 2: Feed ranking and delivery

A feed request hits `get-feed.ts`. The function fetches 3x the requested limit from `v_feed_ranked`, then scores each row: `signal x recency_decay (36-hour half-life) x variance_boost (+30% if variance detected) x novelty_boost (+15% max)`. A diversification pass caps any single figure at 20% of results (minimum 3 per figure). The paginated slice is returned with metadata. Five sort modes available: smart (default), recency, signal, novelty, divergence.

### Path 3: Consensus badge rendering

`consensus_badge.dart` receives a Consensus model. Based on agreement level, model count, and whether variance was detected, it selects one of 37 visual treatments. The widget renders an animated ring gauge via CustomPainter, with the ring fill representing consensus score, color encoding agreement level, and optional variance indicators. The painting logic handles edge cases: missing consensus (shimmer placeholder), single-provider results (partial ring), and split decisions (segmented ring with per-provider colors).

---

## Data Model

30 tables across 5 domains, all with Row Level Security enabled.

**Core Intelligence:**
`figures` (106 rows), `statements` (5,454), `analyses` (16,251), `analyses_audit` (16,251), `consensus` (5,361)

**Legislative Tracking:**
`bill_versions` (364), `bill_summaries` (354), `version_comparisons`, `mutation_diffs` (109), `bill_spending_summary` (50)

**Data Pipeline:**
`raw_ingestion_jobs` (20,921), `pipeline_events` (38,658), `source_hashes` (2,277), `gemini_structured_output` (2,644), `cost_log` (11,224)

**Platform:**
`user_profiles`, `subscriptions`, `subscription_events`, `tier_features` (52), `feature_flags` (16), `rate_limit_entries`, `votes` (161), `annotations`, `waitlist`

**Social:**
`posted_tweets`, `trending_topics`

---

## AI Provider Orchestration

- Same statement sent to Claude, GPT, and Grok independently (Gemini handles extraction, not analysis)
- Each provider returns structured metrics: repetition score, novelty score, affect intensity, entropy, framing label
- Providers never see each other's output
- Consensus engine loads all results, measures inter-model agreement, flags high-variance cases
- Every API call is cost-tracked: provider, model, input/output tokens, estimated USD (11,224 log entries across all providers)
- 4 providers: Claude (Anthropic), GPT-4 (OpenAI), Gemini (Google), Grok (xAI)

---

## Production Stats

| Metric | Count |
|--------|-------|
| Tracked figures | 106 |
| Statements analyzed | 5,454 |
| AI analyses computed | 16,251 |
| Consensus scores | 5,361 |
| Pipeline events | 38,658 |
| Cost log entries | 11,224 |
| Bill versions tracked | 364 |
| Edge Functions | 22 |
| Database tables (all RLS) | 30 |
| Flutter screens | 28 |
| PostgreSQL version | 17 |

---

## What I Would Improve Next

- Add Gemini as a 4th analysis provider (currently handles extraction only)
- Add automated regression tests for Edge Functions (audit flagged this gap)
- Add structured logging and observability beyond pipeline_events (audit flagged this gap)
- Implement real-time WebSocket feed updates (currently polling)
- Build a public API for researchers
- Performance optimization on feed query for 50K+ statements
- Formalize the tradeoffs section into an ADR (Architecture Decision Record) pack

---

## App Access

Baseline is in closed testing on Google Play. Contact [Droiddna2013@gmail.com](mailto:Droiddna2013@gmail.com) for reviewer access.

---

## Related

- [trading-toolkit](https://github.com/Preston2012/trading-toolkit) - Python automation: options scanner, trading bots, VPS infrastructure
- [ai-council](https://github.com/Preston2012/ai-council) - Multi-model AI orchestration methodology (how this was built)
- [baseline.marketing](https://github.com/Preston2012/baseline.marketing) - Marketing site and portfolio
- Portfolio: [baseline.marketing/built](https://baseline.marketing/built)
- LinkedIn: [linkedin.com/in/prestonwinters](https://linkedin.com/in/prestonwinters)
- GitHub: [github.com/Preston2012](https://github.com/Preston2012)
- Contact: [Droiddna2013@gmail.com](mailto:Droiddna2013@gmail.com)
