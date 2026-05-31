# Batch Execution Design

> **Canonical design reference.** For user-facing usage instructions see
> [`docs/batch-execution.md`](../batch-execution.md). For the implementation
> summary produced during the initial feature work see
> [`BATCH_EXECUTION_SUMMARY.md`](../../BATCH_EXECUTION_SUMMARY.md).

## Goals

1. Allow users to run the same contract function against many argument sets in a single invocation.
2. Execute those argument sets in parallel so wall-clock time scales with CPU cores, not input count.
3. Aggregate individual results into a deterministic, human- and machine-readable summary.
4. Keep batch mode a composable layer on top of the existing single-run execution path rather than a separate code path.

## Non-Goals

- Interactive / step-through debugging of individual batch items (use single-run mode for that).
- Ordered / sequential execution (ordering is not guaranteed between items; each item is independent).
- Distributed execution across multiple hosts.

---

## Architecture

### Components

```
CLI (--batch-args <file>)
        │
        ▼
  BatchExecutor (src/batch.rs)
        │
        ├─ load_batch_file()   – deserialise JSON array of BatchItems
        │
        ├─ execute_batch()     – par_iter() over items → Vec<BatchResult>
        │       │
        │       └─ execute_single()  – delegates to ContractExecutor (single-run path)
        │
        ├─ summarize()         – fold Vec<BatchResult> → BatchSummary
        │
        └─ display_results()   – render to stdout (text or JSON)
```

### Key Types

| Type | Location | Purpose |
|------|----------|---------|
| `BatchItem` | `src/batch.rs` | Deserialised entry from the JSON file: `args`, optional `expected`, optional `label` |
| `BatchResult` | `src/batch.rs` | Outcome of a single execution: result value, pass/fail status, duration, error |
| `BatchSummary` | `src/batch.rs` | Aggregate counts (total, passed, failed, errors) and total duration |
| `BatchExecutor` | `src/batch.rs` | Orchestrates the above; receives a shared reference to `ContractExecutor` |

---

## Parallelism Model

Batch execution uses **Rayon's work-stealing thread pool** (`par_iter()`).

```
items: Vec<BatchItem>
        │
        ▼  rayon::par_iter()
┌──────────────────────────────────────┐
│  Thread 0  │  Thread 1  │  Thread N  │   (Rayon pool, N = logical CPU cores)
│  item[0]   │  item[1]   │  item[k]   │
│     ↓      │     ↓      │     ↓      │
│ exec_single│ exec_single│ exec_single│
└──────────────────────────────────────┘
        │
        ▼  collect()
results: Vec<BatchResult>   (order matches input order after collect)
```

**Thread safety constraints:**

- `ContractExecutor` is instantiated fresh per item inside `execute_single`. Each invocation gets its own `soroban-env-host` `Host` instance, so there is no shared mutable state between parallel executions.
- The JSON input file is loaded once on the main thread and shared as an immutable slice.
- Result collection via `collect()` on a `ParallelIterator` is deterministic in output order (Rayon preserves index order for `collect`).

---

## Result Aggregation

After all executions complete, `summarize()` produces a `BatchSummary`:

```rust
BatchSummary {
    total:    usize,   // number of BatchItems run
    passed:   usize,   // items where actual result == expected (or no expected set)
    failed:   usize,   // items where actual result != expected
    errors:   usize,   // items that panicked or returned an execution error
    duration: Duration,// wall-clock time from start of par_iter to end of collect
}
```

### Pass/Fail Logic

| Condition | Classification |
|-----------|----------------|
| No `expected` field set and execution succeeded | **Passed** |
| `expected` field set and `actual == expected` (string comparison) | **Passed** |
| `expected` field set and `actual != expected` | **Failed** |
| Execution returned an error or panicked | **Error** |

---

## Input File Format

```json
[
  {
    "args": "[\"Alice\", \"Bob\", 100]",
    "expected": "void",
    "label": "transfer 100 units"
  },
  {
    "args": "[\"Charlie\", \"Dave\", 0]",
    "label": "zero-value transfer (no assertion)"
  }
]
```

- The top-level value **must** be a JSON array.
- `args` is a **JSON string** (not a nested array) containing the argument list exactly as it would be passed to `--args`.
- `expected` is an optional string compared against the serialised return value.
- `label` is optional and used only for human-readable output.

---

## CLI Integration

```
soroban-debug run \
  --contract path/to/contract.wasm \
  --function transfer \
  --batch-args path/to/batch.json
```

When `--batch-args` is provided:

1. The `run` command delegates to `BatchExecutor::load_batch_file()`.
2. `execute_batch()` is called instead of the normal single-run path.
3. Results are printed to stdout; exit code is `0` if all items pass, non-zero otherwise.

`--batch-args` is mutually exclusive with `--args` in the CLI argument parser.

---

## VS Code Extension

The extension exposes batch mode via the `batchArgs` field in `launch.json`:

```json
{
  "name": "Soroban: Batch Test",
  "type": "soroban",
  "request": "launch",
  "contractPath": "${workspaceFolder}/target/wasm32-unknown-unknown/release/contract.wasm",
  "entrypoint": "transfer",
  "batchArgs": "${workspaceFolder}/tests/batch_inputs.json"
}
```

When `batchArgs` is set the adapter passes `--batch-args` to the spawned `soroban-debug server` process. Breakpoints and stepping are skipped in batch mode; use single-run mode to debug individual failing cases.

---

## Performance Characteristics

| Batch size | Approximate speed-up vs sequential |
|-----------|--------------------------------------|
| 10 items  | ~10×                                 |
| 100 items | ~50× (plateau depends on core count) |

Speed-up is roughly linear up to the Rayon thread-pool size (default: logical CPU count) then plateaus. Contract execution time dominates; scheduling overhead is negligible for all practical batch sizes.

---

## Extension Points

| What to extend | Where |
|---------------|-------|
| New result aggregation strategies (e.g., percentiles, histogram) | `BatchExecutor::summarize()` in `src/batch.rs` |
| Custom assertion formats (e.g., regex match, numeric tolerance) | `BatchItem` struct + `execute_single()` comparison logic |
| Streaming / incremental output | `BatchExecutor::display_results()` — replace `collect` + render with a channel-based sink |
| Different parallelism back-ends (e.g., async, remote dispatch) | Replace `par_iter()` in `execute_batch()` with the desired scheduler |

---

## Related Documents

- [`docs/batch-execution.md`](../batch-execution.md) — user guide with CLI examples and output format
- [`docs/batch-result-buckets.md`](../batch-result-buckets.md) — result classification details
- [`BATCH_EXECUTION_SUMMARY.md`](../../BATCH_EXECUTION_SUMMARY.md) — implementation summary from the original feature PR
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) — system-level overview including the Batch Executor extension point
