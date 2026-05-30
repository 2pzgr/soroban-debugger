# Symbolic Coverage Reporting

## Overview

The Soroban debugger now provides **coverage metrics** for symbolic execution runs, helping you understand how thoroughly your contract was explored. These metrics tell you not just *what* happened during symbolic analysis, but *how complete* the exploration was.

## Coverage Metrics

When you run `soroban-debug symbolic`, the report now includes a **Coverage Summary** section with the following metrics:

### Functions Reached

```
Functions reached: 3/12 (25.0%)
```

This shows:
- **Unique functions reached**: How many contract functions were actually executed during symbolic exploration
- **Total functions available**: The total number of exported functions in the WASM module
- **Percentage**: The ratio of reached to available functions

**Why this matters**: If symbolic execution only reached 25% of your contract's functions, you may need to:
- Increase `--path-cap` to explore more execution paths
- Provide different input combinations that trigger other functions
- Use `--profile deep` for more thorough exploration

### Branches Touched

```
Branches touched: 8 (estimated from distinct paths)
```

This metric estimates branch coverage by counting distinct execution paths discovered. Each unique path through the code represents at least one branch decision that was explored.

**Interpretation**:
- Higher numbers indicate more thorough branch exploration
- This is a *conservative estimate* - each path may actually touch multiple branches
- Use this to gauge whether you're seeing diverse execution flows

### Duplicates Suppressed

```
Duplicates suppressed: 15
```

Shows how many input combinations were skipped because they were identical to previously tested inputs. This happens when:
- The input generation produces redundant combinations
- Multiple input sets lead to the same execution path

**Why this matters**: High duplicate counts suggest:
- Your input generation strategy could be optimized
- The contract may have many equivalent input paths
- Consider using `--seed` to shuffle exploration order

### Exploration Completeness

The report includes an indicator showing whether exploration completed fully:

```
✓ Exploration completed without hitting caps
```

Or warnings if exploration was limited:

```
⚠ Exploration hit path cap - may not be complete
⚠ Exploration timed out - may not be complete
```

**What to do if you see warnings**:
- **Path cap reached**: Increase `--path-cap` (default: 100)
- **Timeout reached**: Increase `--timeout` (default: 30s)
- Consider using `--profile deep` for maximum exploration

## Example Output

```
Function: transfer
Paths explored: 47
Panics found: 2
Replay token: 42
Budget: path_cap=100, input_combination_cap=256, timeout=30s
Input combinations: generated=256, attempted=47, distinct_paths=12

Coverage Summary:
  Functions reached: 3/12 (25.0%)
  Branches touched: 12 (estimated from distinct paths)
  Duplicates suppressed: 35
  ✓ Exploration completed without hitting caps

Truncation: none

Distinct paths:
  1. inputs=["GAAA...", "GBBB...", 100] -> return Ok(Void)
  2. inputs=["GAAA...", "GBBB...", 0] -> panic Error(Contract, #1)
  ...
```

## Interpreting Coverage Results

### Good Coverage Indicators

- **Functions reached > 50%**: Symbolic execution is exploring a significant portion of your contract
- **Low duplicate ratio**: Input generation is efficient and diverse
- **No truncation warnings**: Exploration completed without hitting limits
- **Multiple distinct paths**: Contract logic has been tested under various conditions

### Poor Coverage Indicators

- **Functions reached < 20%**: Many contract functions were never executed
- **High duplicate ratio (>50%)**: Input generation is producing redundant combinations
- **Path cap reached**: You need to increase exploration limits
- **Only 1-2 distinct paths**: Contract may have limited branching or inputs aren't diverse enough

## Improving Coverage

### 1. Increase Exploration Limits

```bash
# Increase path cap to explore more execution paths
soroban-debug symbolic contract.wasm --function transfer --path-cap 500

# Increase timeout for complex contracts
soroban-debug symbolic contract.wasm --function transfer --timeout 120
```

### 2. Use Deep Profile

```bash
# Maximum exploration breadth and depth
soroban-debug symbolic contract.wasm --function transfer --profile deep
```

### 3. Shuffle Exploration Order

```bash
# Use a seed to shuffle input exploration order
soroban-debug symbolic contract.wasm --function transfer --seed 42

# Reproduce the same exploration later
soroban-debug symbolic contract.wasm --function transfer --replay 42
```

### 4. Provide Storage Seeds

```bash
# Test how different storage states affect execution
echo '{"balance_alice": 1000, "balance_bob": 500}' > storage.json
soroban-debug symbolic contract.wasm --function transfer --storage-seed storage.json
```

## Coverage in Scenario TOML

When you export symbolic analysis to a scenario file with `--output`, the coverage metrics are included:

```toml
[metadata]
max_paths = 100
max_input_combinations = 256
timeout_secs = 30
generated_input_combinations = 256
attempted_input_combinations = 47
distinct_paths_recorded = 12
unique_functions_reached = 3
total_functions_available = 12
branches_touched = 12
duplicates_suppressed = 35
exploration_cap_reached = false
```

This allows you to:
- Track coverage improvements over time
- Compare coverage between contract versions
- Ensure consistent coverage in CI/CD pipelines

## Technical Details

### How Coverage is Calculated

1. **Functions reached**: Counts unique exported functions that were successfully invoked during symbolic execution
2. **Total functions**: Extracted from WASM export section using `wasmparser`
3. **Branches touched**: Conservative estimate based on distinct execution paths (each path represents ≥1 branch)
4. **Duplicates**: Calculated as `paths_explored - distinct_paths_recorded`

### Limitations

- **Function coverage** only tracks the top-level function being tested, not internal helper functions
- **Branch coverage** is an approximation - true branch coverage would require instrumenting WASM bytecode
- **Cross-contract calls** are not tracked in coverage metrics (only the target contract's functions)

### Future Enhancements

Potential improvements for more accurate coverage:
- Instrument WASM to track internal function calls
- Parse WASM control flow to count actual branches (if/else, br_if, etc.)
- Track basic block coverage within functions
- Integrate with DWARF debug info for source-level coverage

## Use Cases

### 1. Pre-Deployment Validation

Before deploying to mainnet, ensure symbolic execution explored sufficient coverage:

```bash
REPORT=$(soroban-debug symbolic contract.wasm --function transfer --profile deep)
COVERAGE=$(echo "$REPORT" | grep "Functions reached" | awk '{print $4}' | tr -d '()')
if (( $(echo "$COVERAGE < 50.0" | bc -l) )); then
  echo "WARNING: Coverage below 50%, review before deployment"
  exit 1
fi
```

### 2. Regression Testing

Compare coverage between contract versions to ensure new code is exercised:

```bash
# Version 1.0
soroban-debug symbolic v1.0.wasm --function transfer --output v1_scenario.toml

# Version 2.0
soroban-debug symbolic v2.0.wasm --function transfer --output v2_scenario.toml

# Compare coverage metrics
diff <(grep "functions_reached" v1_scenario.toml) <(grep "functions_reached" v2_scenario.toml)
```

### 3. CI/CD Integration

Add coverage thresholds to your CI pipeline:

```yaml
# .github/workflows/symbolic-analysis.yml
- name: Symbolic Coverage Check
  run: |
    OUTPUT=$(soroban-debug symbolic target/wasm32-unknown-unknown/release/contract.wasm --function main --profile deep)
    echo "$OUTPUT" | grep -q "Exploration hit path cap" && exit 1
    echo "$OUTPUT" | grep -q "Functions reached: 0" && exit 1
```

## Best Practices

1. **Always check coverage metrics** after symbolic execution runs
2. **Use `--profile deep`** for contracts with complex branching logic
3. **Set appropriate caps** - too low and you miss coverage, too high and you waste time
4. **Use seeds** for reproducible coverage in CI/CD
5. **Export scenarios** to track coverage history over time
6. **Combine with other analysis** - use `analyze`, `profile`, and `compare` commands for complete picture

## Related Documentation

- [Symbolic Execution Tutorial](../tutorials/symbolic-analysis-budgets.md)
- [Performance Optimization Guide](optimization-guide.md)
- [Feature Matrix](feature-matrix.md)
