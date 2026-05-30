# Source-Level Debugging in Soroban Debugger

This document describes the architecture and implementation of source-level debugging for Soroban smart contracts.

## Overview

Soroban contracts are compiled from Rust to WebAssembly (WASM). While debugging the WASM bytecode directly is powerful, it is orignally more efficient for developers to see the corresponding Rust source code. The debugger achieves this by parsing DWARF debug information embedded in the WASM binary.

## Architecture

1. **DWARF Parsing**: The `SourceMap` module (`src/debugger/source_map.rs`) uses the `gimli` and `addr2line` crates to parse DWARF sections (`.debug_info`, `.debug_line`, etc.) from the WASM binary.
2. **Offset Mapping**: It builds a mapping from WASM instruction offsets to source locations (file path, line number, column).
3. **Source Management**: A source cache is maintained to avoid repeated disk reads when displaying code.
4. **Engine Integration**: The `DebuggerEngine` uses the `SourceMap` to resolve the current instruction's location and provides a `step_source` method for line-by-line stepping.
5. **UI Visualization**: The TUI Dashboard features a dedicated Source pane that highlights the current line and centers the view automatically.

## Requirements & Implementation

- **DWARF Support**: Full support for standard DWARF embedded in WASM.
- **Source Line Stepping**: Integrated into the stepping logic.
- **Caching**: Performance optimized with file and mapping caches.
- **Fallback & Diagnostics**: Graceful fallback to WASM-only view if debug info is missing or stripped. When DWARF metadata is partially malformed, `SourceMap::load` continues to extract valid data and surfaces parsing errors as warnings (`SourceMapDiagnostic`) rather than completely aborting. These diagnostics can be reviewed using `inspect`.

## When DWARF Is Absent: Heuristic Fallback

Production Soroban WASM binaries are commonly stripped of debug symbols to reduce size. When the debugger cannot find valid DWARF sections in the binary, it does not fail outright — it switches to a heuristic fallback mode.

### What the heuristic fallback does

Instead of using DWARF to map instruction offsets to source lines, the debugger falls back to **function-level mapping**: it identifies exported contract entrypoint functions from the WASM export table and maps breakpoints to those function boundaries.

This means:

- **Source breakpoints become function breakpoints.** A breakpoint set on `src/lib.rs:10` will be matched heuristically to the nearest exported function that contains that line (if one can be inferred). Execution still pauses, but at the function entry rather than at the exact line.
- **Step-by-step source navigation is unavailable.** The Source pane falls back to a WASM instruction view because there are no line mappings to follow.
- **The `HEURISTIC_NO_DWARF` reason code is set.** When the VS Code adapter reports breakpoint status, it uses `verified=false` and `reasonCode=HEURISTIC_NO_DWARF` to signal that the mapping is approximate.

### Breakpoint response fields under heuristic fallback

| Field | Value | Meaning |
|---|---|---|
| `verified` | `false` | No exact source-to-runtime proof was available. |
| `reasonCode` | `HEURISTIC_NO_DWARF` | DWARF was absent; heuristic function mapping was used instead. |
| `setBreakpoint` | `true` (if matched) | A runtime function breakpoint was still installed. |

### How to get full source-level debugging

Compile your contract with debug symbols:

```bash
cargo build   # debug build retains DWARF by default
```

Avoid passing `--release` or running `wasm-opt` on the binary you intend to debug, as both strip or alter debug sections.

### Diagnosing fallback mode

Run `inspect` on the binary to see which fallback mode the debugger will use and whether any partial DWARF data was recoverable:

```text
inspect <contract.wasm>
```

The output includes a source-map health summary that reports mapping coverage and the active fallback mode. See also [source-map-health.md](source-map-health.md) and the [FAQ entry on `verified=false` breakpoints](faq.md).

## Limitations

- **Stripped Binaries**: Production Soroban WASM files are often stripped to save space. Debug info is only available in binaries compiled with debug symbols (e.g., `cargo build`).
- **Optimization**: Highly optimized WASM (via `wasm-opt`) may have slightly inaccurate line mappings due to code movement and inlining.
- **Path Resolution**: DWARF often contains absolute paths from the build machine. If debugging on a different machine, source file loading may fail if paths don't match.

## Source Breakpoint Semantics

When setting a source breakpoint from VS Code, the adapter reports extra diagnostic details so users can distinguish source validation from runtime breakpoint behavior.

- `verified`: Whether the adapter can prove an exact source-to-runtime mapping from debug metadata (for example, DWARF).
- `setBreakpoint`: Whether the adapter will still install a runtime function breakpoint even if source verification is not available.
- `HEURISTIC_NO_DWARF`: Reason code used when DWARF source mappings are unavailable but a best-effort function mapping is still possible.

Concrete example:

- You set a source breakpoint on `src/lib.rs:10`.
- The adapter returns `verified=false`, `reasonCode=HEURISTIC_NO_DWARF` and a diagnostic message.
- If line 10 maps heuristically to an exported contract entrypoint, `setBreakpoint=true` and execution still pauses when that function is reached.

## Testing

Unit tests in `tests/source_map_test.rs` verify the lookup logic using mock mappings.
