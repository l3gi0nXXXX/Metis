# Metis Memory Parity Matrix

This document tracks one-to-one parity work between the current Magic CLI memory system and the upstream `memory-core` implementation.

Status labels:
- `done`: behavior is already close enough to treat as implemented
- `partial`: implemented, but not yet upstream-equivalent
- `missing`: not yet implemented

## Module Matrix

| Reference module | Current Cangjie location | Status | Gap |
| --- | --- | --- | --- |
| `bootstrap-files.ts` / workspace bootstrap loading | `src/core/prompting/metis_workspace_bootstrap.cj` | `partial` | File discovery exists, but budget/override/session filtering is not yet one-to-one. |
| `tools.ts` memory tool surface | `src/core/tools/memory_toolset.cj` | `partial` | `memory_search` / `memory_get` exist and now resolve search through a reference-style memory search manager lifecycle, with search backend and orchestration backend separated. Native `qmd` search, status, and manual indexing are wired; citations/remote embedding parity is still missing. |
| `short-term-promotion.ts` | `src/core/memory/short_term_promotion.cj` + `src/core/memory/local_memory_index.cj` | `partial` | State, audit, signals, lock handling, reference-style default thresholds, and default promotion weights now exist in a dedicated runtime; ranking/orchestration still relies on the local provider implementation. |
| `dreaming-markdown.ts` | `src/core/memory/dreaming_markdown.cj` | `done` | Managed block writing, separate reports, and `inline/separate/both` storage policy now exist as a dedicated runtime. |
| `dreaming-narrative.ts` | `src/core/memory/dreaming_narrative.cj` | `partial` | Dedicated run/wait/messages/delete/generate+append runtime surface now exists with an explicit `SubagentSurface`-style adapter, managed diary-section writes, internal system-prompt injection, and transient prompt/run cleanup, but it still uses the local planner CLI bridge rather than the full upstream subagent runtime. |
| `dreaming-phases.ts` | `src/core/memory/dreaming_phases.cj` + `src/core/memory/local_memory_index.cj` + `src/core/memory/daily_ingestion.cj` + `src/app/memory_command.cj` | `partial` | `light/rem/deep/all`, daily ingestion, managed cron reconciliation, and system-event execution now exist; `local_memory_index.cj` now acts as an internal provider behind the runtime facade. |
| `dreaming.ts` deep dreaming flow | `src/core/memory/local_memory_index.cj` | `partial` | Deep phase now owns durable promotion while light/rem only stage and reflect, but the consolidation/report structure is still lighter than the reference implementation. |
| `memory-state.ts` | `src/core/memory/memory_state.cj` | `partial` | Explicit status/index/fix/path registry now fronts the active search backend, while durable-memory promotion/dreaming orchestration flows through a separate backend layer; the model is still lighter than the full upstream plugin state system. |
| `memory-runtime.ts` | `src/core/memory/memory_runtime.cj` | `partial` | Runtime entrypoints and dreaming constants now dispatch through separate search-backend and orchestration-backend registry surfaces with `resolveMemoryBackendConfig`, `getMemorySearchManager`, and `closeAllMemorySearchManagers`, but the provider model is still lighter than the full upstream plugin runtime. |
| `runtime-provider.ts` / backend resolution | `src/core/memory/memory_provider_registry.cj` | `partial` | Pluggable search backend registration/activation and lifecycle-style backend resolution now exist with a distinct local orchestration backend. `local` uses sqlite-fts; `builtin` uses pure file-scan search; `external` supports qmd-like command-driven search backends; native `qmd` now has isolated state, managed collections, session export, scope-gated session recall, boot maintenance, and manual update/embed indexing. Remote/vector backends and richer mcporter/session manager parity are still missing. |
| memory CLI runtime | `src/app/memory_command.cj` | `partial` | Surface now includes reference-style aliases/flags like `promote-explain`, `search --query/--max-results`, and `/dreaming`, but output formatting is still local rather than fully identical. |
| compaction flush hooks | `src/core/conversation/conversation_manager.cj` | `partial` | Flush and reindex exist, but not yet modeled as memory flush plan/runtime hooks. |

## Behavior Matrix

### Search / Retrieval

| Capability | Status | Notes |
| --- | --- | --- |
| `memory_search` tool | `done` | SQLite FTS + fallback file scan implemented. |
| `memory_get` tool | `done` | Reads `MEMORY.md`, `memory.md`, and `memory/` safely. |
| citations mode / runtime backend selection | `partial` | Search backend selection now exists for `local`, `builtin`, `external`, and native `qmd`. Search resolves through a memory search manager lifecycle, durable-memory orchestration is no longer tied to the search backend, and qmd now supports isolated collections/session export/update/embed, but citations/remote embedding parity is still missing. |

### Short-Term Recall

| Capability | Status | Notes |
| --- | --- | --- |
| recall store file | `done` | `~/.metis/memory/short-term-recall.json` exists. |
| `queryHashes` | `done` | Stored as hashed values rather than normalized raw query text. |
| `recallDays`, `dailyCount`, `promotedAt` | `done` | Present. |
| phase signal store | `done` | Dedicated phase signal artifact exists. |
| lock / stale lock handling | `done` | Short-term promotion lock and stale lock cleanup exist. |
| audit / repair semantics | `partial` | Short-term audit summary, issue taxonomy, default threshold/weight exposure, and repair exist, but still lighter than the reference implementation. |

### Promotion

| Capability | Status | Notes |
| --- | --- | --- |
| ranking and preview | `done` | Present with recall/diversity/recency/concept tags. |
| `promote --json` | `done` | Present. |
| `promote explain` | `done` | Present. |
| `include-promoted` | `done` | Present. |
| reference-equivalent weights / thresholds | `partial` | Similar structure, not same formulas/config surface. |

### Dreaming

| Capability | Status | Notes |
| --- | --- | --- |
| `light` phase | `partial` | Present, now driven by daily ingestion + phase signal model and no longer writes durable memory directly, but still lighter than the reference orchestration. |
| `rem` phase | `partial` | Present, with daily ingestion and managed reports, but reflection selection still simplified. |
| `deep` phase | `partial` | Present and now solely responsible for durable promotion into `MEMORY.md`, but still far simpler than the reference deep dreaming flow. |
| managed phase blocks in `DREAMS.md` | `done` | Implemented with configurable `inline/separate/both` storage policy. |
| separate phase reports | `done` | `memory/dreaming/<phase>/<day>.md` exists. |
| narrative generation | `partial` | Uses a dedicated `SubagentSurface`-style narrative runtime with managed diary appends, real extra-system-prompt injection, and transient run cleanup, but the backend still relies on the internal planner bridge + fallback rather than the full upstream subagent runtime. |
| startup cron reconciliation | `done` | `gateway serve` now reconciles managed light/rem dreaming cron jobs at startup. |
| heartbeat/system-event execution | `partial` | Managed cron `systemEvent` now executes dreaming phases in `CronRunner`, but there is still no full reference hook/runtime bus. |

## Execution Plan Mapping

1. Move logic from `local_memory_index.cj` into explicit boundary modules:
   - `short_term_promotion.cj`
   - `daily_ingestion.cj`
   - `dreaming_markdown.cj`
   - `dreaming_narrative.cj`
   - `dreaming_phases.cj`
2. Make new modules the source of truth and gradually reduce `local_memory_index.cj` to orchestration/facade.
3. Add missing state/runtime layers:
   - `memory_state.cj`
   - `memory_runtime.cj`
4. Align daily ingestion, phase signals, and cron/heartbeat triggers with the upstream runtime.
5. Align CLI/runtime schemas and regression coverage.
