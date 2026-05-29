# Symbolic Analysis Budgets

The `symbolic` command now supports deterministic exploration budgets so you can tune analysis depth for local debugging and CI.

## Preset profiles

Use `--profile` to start from a preset:

- `fast`: small budget for quick feedback
- `balanced`: default budget for everyday use
- `deep`: larger budget for more exhaustive exploration

Example:

```bash
soroban-debug symbolic \
  --contract ./target/wasm32-unknown-unknown/release/my_contract.wasm \
  --function transfer \
  --profile balanced
```

## Explicit caps

Override any preset dimension with explicit flags:

```bash
soroban-debug symbolic \
  --contract ./target/wasm32-unknown-unknown/release/my_contract.wasm \
  --function transfer \
  --profile fast \
  --input-combination-cap 128 \
  --path-cap 64 \
  --timeout 20
```

Flags:

- `--input-combination-cap`: maximum number of generated input combinations
- `--path-cap`: maximum number of generated inputs to execute
- `--timeout`: overall symbolic-analysis timeout in seconds

## Truncation metadata

Symbolic reports now explain whether exploration was truncated by:

- input combination cap
- path exploration cap
- timeout

Generated scenario TOML files include a `[metadata]` section with the applied budget and truncation reasons, which is useful for CI artifacts and reproducible investigations.

## Interpreting the Exploration Report

When symbolic analysis completes, the debugger outputs an exploration report summarizing the execution paths discovered and the potential vulnerabilities found.

A typical report includes:

1. **Exploration Summary:** The total number of paths analyzed, inputs generated, and whether the exploration was truncated due to budget limits.
2. **Vulnerability Findings:** A list of critical issues detected, such as panics, out-of-bounds access, or unhandled errors. Each finding points to the specific code location and the input combination that triggers it.
3. **Coverage Metrics:** An overview of which contract branches were exercised by the generated paths.

If the report indicates truncation (e.g., `Truncation Reason: timeout`), it means the analysis did not exhaustively search all possible states. To gain more confidence, you may need to run it again with a `deep` profile or a higher `--timeout`.

## Acting on Findings

Once you have identified issues in the report, take the following steps to resolve them:

1. **Reproduce the Issue:** Use the generated scenario TOML files to run the exact inputs that caused the failure. You can replay these scenarios using the `soroban-debug run --scenario` command to step through the execution interactively.
2. **Add Defensive Checks:** If a panic or vulnerability is triggered by an unexpected input, add explicit assertions or handle the edge case gracefully in your Rust code.
3. **Refine Analysis Budgets:** If the exploration hits the `path-cap` before reaching critical code paths, consider increasing the budget caps or restricting the input space (using constraints) to focus the engine on specific contract states.
4. **Iterate:** After applying your fixes, rerun the symbolic analysis to confirm the vulnerability is resolved and no new regressions were introduced.
## JSON schema

Machine-readable symbolic reports are emitted with `--format json` and use the shared command envelope:

```json
{
  "schema_version": "1.0.0",
  "command": "symbolic",
  "status": "success",
  "result": {},
  "error": null
}
```

The current symbolic report schema is `tests/schemas/symbolic_output.json` and expects envelope `schema_version` `1.0.0`. The `result.metadata` object includes the applied seed or replay token, optional `storage_seed`, budget caps, truncation flags, truncation reasons, and coverage metadata so CI consumers can detect partial exploration and suggest raising `--input-combination-cap`, `--path-cap`, or `--timeout` when needed.
