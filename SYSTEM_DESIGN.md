# Baseline System Design

## Problem Statement

Political accountability requires tracking what public figures say, analyzing whether their statements align with their actions, and presenting this data in a way citizens can understand. No single AI model is reliable enough alone for this analysis. Manual tracking doesn't scale.

## Solution: Multi-Provider AI Consensus

Baseline solves this by treating AI analysis like a peer review system. Every statement goes through 4 independent AI providers. Each provider analyzes the statement without seeing the others' output. A consensus algorithm then reconciles the results.

### Why Multi-Provider?

Single-model AI analysis has known failure modes: hallucination, political bias, recency bias, and inconsistent reasoning. By running 4 providers independently and comparing outputs, Baseline can:

- Identify high-confidence analyses (all providers agree)
- Flag uncertain analyses (providers disagree)
- Detect provider-specific biases over time
- Maintain analysis quality even if one provider degrades

## Data Flow

```
[Official Sources] --> [Ingestion Pipeline] --> [Statement Storage]
                                                       |
                                                       v
                                              [Analysis Router]
                                             /    |    |    \
                                          Claude GPT  Gem  Grok
                                             \    |    |    /
                                              [Consensus Engine]
                                                       |
                                                       v
                                              [Scored Statement]
                                                       |
                                                       v
                                              [Feed / Profiles / Trends]
```
## Pipeline Architecture

### Stage 1: Ingestion
Statements are ingested from official sources via automated workflows (Make.com) and on-demand triggers. Each source is hashed to prevent duplicate processing. Raw ingestion jobs are logged (20,900+ processed).

### Stage 2: Analysis
The `analyze-statement` Edge Function routes each statement to all 4 AI providers in parallel. Each provider returns structured analysis independently. All analyses are stored with full audit trails (16,200+ analyses with matching audit records).

### Stage 3: Consensus
The `compute-consensus` function takes all provider analyses for a statement and produces a single consensus score. The algorithm weights provider agreement, confidence levels, and historical accuracy. [Scoring methodology is proprietary.]

### Stage 4: Enrichment
- `get-baseline-score`: Computes aggregate reliability scores per figure
- `get-narrative-sync`: Measures consistency of a figure's positions over time
- `get-trends`: Identifies trending topics and shifting positions
- `generate-embedding`: Creates vector embeddings for semantic search

### Stage 5: Legislative Correlation
A parallel pipeline tracks legislative activity:
- `sync-bill-versions`: Pulls bill versions from Congress.gov
- `compute-bill-mutation`: Diffs versions to find changes
- `summarize-bill`: AI-powered plain-language summaries
- Spending data extraction and anomaly detection

## Scalability Decisions

| Decision | Rationale |
|----------|-----------|
| Edge Functions over traditional server | Global low-latency, zero server management, scales to zero |
| PostgreSQL with RLS over NoSQL | Relational data (figures > statements > analyses) maps naturally. RLS provides row-level security without app-level auth checks |
| 4 providers over 1 | Consensus quality. Cost tracked per-call (11,200+ entries) to optimize spend |
| Structured output via Gemini | Used for specific extraction tasks where structured JSON output is critical |
| Source hashing | Deduplication at ingestion prevents wasted AI spend on reprocessed statements |
| Audit table mirroring | Every analysis has an audit twin for compliance and debugging |

## Security Model

- Row Level Security (RLS) enabled on all 30 tables
- JWT verification on sensitive Edge Functions
- API keys stored in environment variables, never in code
- Subscription entitlement checks via RevenueCat webhooks
- Rate limiting infrastructure in place

## Cost Management

Every AI API call logs to `cost_log` (11,200+ entries). This enables:
- Per-provider cost analysis
- Per-figure analysis cost tracking
- Budget alerts and spend optimization
- ROI measurement across providers