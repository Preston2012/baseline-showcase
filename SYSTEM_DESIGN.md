# Baseline System Design

## Problem Statement

Political accountability requires tracking what public figures say, analyzing whether their statements align with their actions, and presenting this data in a way citizens can understand. No single AI model is reliable enough alone for this analysis. Manual tracking does not scale.

## Solution: Multi-Provider AI Consensus

Baseline treats AI analysis like a peer review system. Every statement goes through 4 independent AI providers. Each provider analyzes the statement without seeing the others' output. A consensus algorithm then reconciles the results.

### Why Multi-Provider?

Single-model AI analysis has known failure modes: hallucination, political bias, recency bias, and inconsistent reasoning. By running 4 providers independently and comparing outputs, Baseline can:

- Identify high-confidence analyses (all providers agree)
- Flag uncertain analyses (providers disagree)
- Detect provider-specific biases over time
- Maintain analysis quality even if one provider degrades

## Data Flow

```
[Official Sources] --> [Ingestion Pipeline] --> [Source Hashing + Dedup]
                                                       |
                                                       v
                                              [Extraction (Gemini)]
                                                       |
                                                       v
                                              [Analysis Router]
                                             /       |       \
                                          Claude    GPT     Grok
                                             \       |       /
                                              [Consensus Engine]
                                                       |
                                              [Variance Detection]
                                                       |
                                                       v
                                              [Scored Statement]
                                                       |
                                                       v
                                              [Feed / Profiles / Trends]
```

## Pipeline Architecture

### Stage 1: Ingestion
Statements are ingested from official sources via automated workflows (n8n) and on-demand triggers. Each source is hashed to prevent duplicate processing. Raw ingestion jobs are logged (20,921 processed). Five dedup layers catch different failure modes: same URL re-crawled, same text from different sources, same statement re-triggered, same analysis re-run.

### Stage 2: Extraction
Gemini handles structured extraction. It parses raw statement text into structured fields (figure attribution, date, context, topics) using JSON-mode output. This is separated from analysis because extraction requires structured output fidelity, not reasoning depth.

### Stage 3: Analysis
The `analyze-statement` Edge Function routes each statement to Claude, GPT, and Grok in parallel via `Promise.allSettled`. Each provider returns structured metrics: repetition, novelty, affective language rate, topic entropy, and a framing label. All analyses are stored with full audit trails (16,251 analyses with matching audit records). Every API call logs to `cost_log` with token counts and estimated USD (11,224 entries).

### Stage 4: Consensus
The `compute-consensus` function takes all provider analyses for a statement and produces a consensus result. The algorithm:
1. Computes per-metric averages and standard deviations across providers
2. Measures inter-provider spread (mean of metric stddevs)
3. Classifies agreement level (high, moderate, low, split)
4. Detects variance when any metric stddev exceeds the threshold
5. Identifies the outlier provider (highest mean deviation from consensus)
6. Determines framing consensus via majority vote
7. Computes signal rank from weighted metric combination

5,361 consensus scores generated.

### Stage 5: Enrichment
- `get-baseline-score`: Computes aggregate reliability scores per figure
- `get-narrative-sync`: Measures consistency of a figure's positions over time
- `get-trends`: Identifies trending topics and shifting positions
- `generate-embedding`: Creates vector embeddings for semantic search

### Stage 6: Legislative Correlation
A parallel pipeline tracks legislative activity:
- `sync-bill-versions`: Pulls bill versions from Congress.gov (364 tracked)
- `compute-bill-mutation`: Diffs versions to find changes
- `summarize-bill`: AI-powered plain-language summaries
- Spending data extraction and anomaly detection

## Scalability Decisions

| Decision | Rationale |
|----------|-----------|
| Edge Functions over traditional server | Global low-latency, zero server management, scales to zero |
| PostgreSQL with RLS over NoSQL | Relational data (figures > statements > analyses) maps naturally. RLS provides row-level security without app-level auth checks |
| 3 analysis providers + 1 extraction provider | Consensus quality. Gemini for extraction (structured output), Claude/GPT/Grok for analysis (reasoning depth). Cost tracked per-call (11,224 entries) to optimize spend |
| Structured output via Gemini | Used for extraction tasks where structured JSON output fidelity is critical |
| 5-layer source dedup | Early duplicates corrupted consensus scores. Each layer catches a different failure mode |
| Audit table mirroring | Every analysis has an audit twin for compliance and debugging |

## Security Model

- Row Level Security (RLS) enabled on all 30 tables
- JWT verification on sensitive Edge Functions
- API keys stored in environment variables, never in code
- Subscription entitlement checks via RevenueCat webhooks with signed tokens
- Rate limiting infrastructure with per-endpoint, per-tier quotas
- Constant-time auth comparison on webhook endpoints

## Cost Management

Every AI API call logs to `cost_log` (11,224 entries). This enables:
- Per-provider cost analysis (revealed GPT-4 at roughly 10x Gemini's cost per call)
- Per-figure analysis cost tracking
- Budget alerts and spend optimization
- Provider routing decisions based on cost/quality tradeoffs
