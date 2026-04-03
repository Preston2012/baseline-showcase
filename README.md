# Baseline - Political Intelligence Platform

> Multi-provider AI analysis of public figures' statements with consensus scoring.
> Solo-built. Google Play approved (closed testing).

[![Live Site](https://img.shields.io/badge/Live-baseline.marketing-blue)](https://baseline.marketing)
[![Google Play](https://img.shields.io/badge/Google%20Play-Approved-green)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B)]()
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%2017-3ECF8E)]()

---

## What Baseline Does

Baseline tracks **106 public figures** across the political spectrum, ingests their public statements from official sources, analyzes each statement through **4 independent AI providers**, and computes a **consensus score** that measures alignment between what politicians say and what they do.

**Production stats:**
- 5,400+ statements ingested and analyzed
- 16,200+ individual AI analyses computed
- 5,300+ consensus scores generated
- 364 legislative bill versions tracked
- 38,600+ pipeline events processed
- Real-time cost tracking across all AI providers

---

## Architecture Overview
```
Flutter App (28 screens)
    |
    v
Supabase (PostgreSQL 17 + Row Level Security)
    |
    +-- 22 Edge Functions (TypeScript/Deno)
    |       |
    |       +-- Statement Ingestion Pipeline
    |       |       manual-ingest-trigger
    |       |       get-feed
    |       |       backfill-baseline
    |       |
    |       +-- Multi-Provider AI Analysis
    |       |       analyze-statement --> [Claude | GPT-4 | Gemini | Grok]
    |       |       compute-consensus
    |       |       generate-embedding
    |       |       get-baseline-score
    |       |
    |       +-- Legislative Tracking
    |       |       sync-bill-versions
    |       |       ingest-bill-version
    |       |       compute-bill-mutation
    |       |       summarize-bill
    |       |
    |       +-- Data & API Layer
    |               get-statement
    |               get-figure-profile
    |               get-narrative-sync
    |               get-trends
    |               get-votes / sync-votes
    |               get-receipt
    |
    +-- 30 Tables with RLS
    +-- RevenueCat (subscription management)
    +-- Automation Workflows (Make.com)
```
## Tech Stack

| Layer | Technology | Details |
|-------|-----------|---------|
| **Mobile** | Flutter 3.x / Dart | 28 screens, Material Design 3, responsive layout |
| **Backend** | Supabase | PostgreSQL 17, Row Level Security on all 30 tables |
| **Serverless** | Deno Edge Functions | 22 functions, TypeScript, deployed globally |
| **AI Providers** | OpenAI, Anthropic, Google, xAI | GPT-4, Claude, Gemini, Grok |
| **Consensus** | Custom scoring engine | Multi-provider reconciliation with confidence weighting |
| **Legislative** | Congress.gov API | Bill version tracking, mutation diffing, spending analysis |
| **Embeddings** | Vector search | Semantic similarity across statements |
| **Payments** | RevenueCat | Subscription tiers with entitlement checking |
| **Automation** | Make.com | 9 workflows for data pipeline orchestration |
| **Hosting** | Google Play | Approved for closed testing |

## Database Schema (30 tables)

**Core Intelligence:**
`figures` (106 rows) | `statements` (5,454) | `analyses` (16,251) | `analyses_audit` (16,251) | `consensus` (5,361)

**Legislative Tracking:**
`bill_versions` (364) | `bill_summaries` (354) | `version_comparisons` | `mutation_diffs` (109) | `bill_spending_summary` (50)

**Data Pipeline:**
`raw_ingestion_jobs` (20,921) | `pipeline_events` (38,658) | `source_hashes` (2,277) | `gemini_structured_output` (2,644) | `cost_log` (11,224)

**Platform:**
`user_profiles` | `subscriptions` | `subscription_events` | `tier_features` (52) | `feature_flags` (16) | `rate_limit_entries` | `votes` (161) | `annotations` | `waitlist`
## Key Features

- **Multi-Provider AI Consensus:** Every statement is analyzed independently by 4 AI providers. A consensus scoring algorithm reconciles outputs to produce a single reliability score. This eliminates single-model bias.
- **Legislative Bill Tracking:** Automatically syncs bill versions from Congress.gov, computes mutations between versions, summarizes changes, and tracks spending implications.
- **Real-Time Feed:** Aggregated feed of analyzed statements with filtering by figure, topic, party, and consensus score.
- **Figure Profiles:** Detailed profiles for each tracked figure with historical analysis, narrative sync scores, and trend data.
- **Embedding Search:** Vector-based semantic search across all statements for finding related political positions.
- **Cost Tracking:** Every AI API call is logged with cost data for budget management across providers.
- **Subscription System:** RevenueCat integration with tiered access, entitlement checking, and webhook handling.

## 22 Edge Functions

| Function | Purpose |
|----------|---------|
| `analyze-statement` | Routes statements to 4 AI providers for independent analysis |
| `compute-consensus` | Reconciles multi-provider analyses into consensus scores |
| `get-baseline-score` | Computes overall reliability scores per figure |
| `get-feed` | Serves the main statement feed with filtering and pagination |
| `get-figure-profile` | Returns complete figure profiles with historical data |
| `get-narrative-sync` | Measures alignment between a figure's statements over time |
| `get-trends` | Computes trending topics and figures |
| `get-statement` | Returns detailed statement with all analyses |
| `generate-embedding` | Creates vector embeddings for semantic search |
| `manual-ingest-trigger` | Triggers statement ingestion pipeline on demand |
| `backfill-baseline` | Backfills historical data for new figures |
| `sync-bill-versions` | Syncs latest bill versions from Congress.gov |
| `ingest-bill-version` | Processes and stores individual bill versions |
| `compute-bill-mutation` | Diffs bill versions to identify changes |
| `summarize-bill` | AI-powered bill summarization |
| `sync-votes` | Syncs voting records |
| `get-votes` | Returns voting data for figures |
| `get-receipt` | Returns AI analysis cost receipts |
| `check-entitlement` | Validates subscription tier access |
| `revenuecat-webhook` | Handles subscription lifecycle events |
| `manage-account` | User account management |
| `annotations` | User annotation system for statements |
## Why These Architectural Choices

- **Multi-provider over single-model:** Single AI models hallucinate, carry political bias, and degrade silently. Running 4 providers independently and reconciling via consensus eliminates single-model failure modes.
- **Edge Functions over traditional server:** Global low-latency, scales to zero, no server management. 22 functions deployed globally via Deno.
- **RLS over app-layer auth:** Row Level Security pushes access control into the database. Every query is filtered at the PostgreSQL level — no auth bugs from missed middleware.
- **Cost tracking as a first-class feature:** Every AI API call logs to `cost_log` with token counts and estimated cost. 11,200+ entries enable per-provider ROI analysis and budget alerts.
- **Source hashing for dedup:** Prevents wasted AI spend by detecting duplicate statements at ingestion time before they hit the analysis pipeline.

## Project Structure

```
baseline/
  lib/                          # Flutter app (28 screens)
    screens/                    # UI screens
    widgets/                    # Reusable components
    services/                   # API and data services
    models/                     # Data models
    providers/                  # State management
    theme/                      # Design system
  supabase/
    functions/                  # 22 Edge Functions (TypeScript)
    migrations/                 # SQL migrations
  assets/                       # Images, icons, fonts
  test/                         # Test suites
```

## Reliability & Observability

- **Pipeline events:** 38,600+ events logged across ingestion, analysis, and consensus stages. Every failure is captured with context for debugging.
- **Cost observability:** Per-provider, per-figure cost tracking across 11,200+ API calls. Budget alerts prevent runaway spend.
- **Graceful degradation:** Non-critical services (xAI, RevenueCat, Make.com webhooks) fail silently without blocking core analysis flow. Kill switch halts the pipeline instantly if needed.
- **Audit trail:** Every AI analysis has a mirrored audit record. Full provenance from raw ingestion through consensus scoring.

---

## App Access & Full Codebase

Baseline is in **Google Play closed testing**. This showcase repo demonstrates architecture and code quality — the full production codebase (28 screens, 22 Edge Functions, 100K+ lines) is available via private repo access.

**Request access:** [Droiddna2013@gmail.com](mailto:Droiddna2013@gmail.com)
**Portfolio:** [baseline.marketing/built](https://baseline.marketing/built)
**LinkedIn:** [Preston Winters](https://linkedin.com/in/prestonwinters)
**GitHub:** [Preston2012/baseline-showcase](https://github.com/Preston2012/baseline-showcase)
