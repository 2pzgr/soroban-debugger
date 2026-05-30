# Tutorial: Set Up the VS Code Extension

This tutorial walks through the full VS Code debugger setup: install the extension, create a `launch.json`, place breakpoints in Rust source, and start a Soroban debug session without leaving the editor.

## Prerequisites

- VS Code installed locally.
- A Soroban contract workspace with a compiled WASM artifact that still contains debug symbols.
- The `soroban-debug` CLI available either on your `PATH` or built in this repository at `target/debug/soroban-debug`.

If you have not built a debug-friendly contract yet, start with [First Debug Session](first-debug.md) and return here once you have a `.wasm` file under `target/wasm32-unknown-unknown/release/`.

## 1. Install the extension

The repository currently documents a local install flow based on a packaged VSIX.

Build the extension from the repository:

```bash
cd extensions/vscode
npm install
npm run build
vsce package
```

This produces a file named `soroban-debugger-<VERSION>.vsix`.

Install that VSIX in VS Code:

1. Open VS Code.
2. Open the Extensions view.
3. Run `Extensions: Install from VSIX...` from the Command Palette.
4. Select the generated `soroban-debugger-<VERSION>.vsix` file.

For extension internals and the full argument reference, see the [VS Code extension README](../../extensions/vscode/README.md).

## 2. Create `.vscode/launch.json`

Create a `.vscode/launch.json` file in your contract workspace:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Soroban: Debug hello_world",
      "type": "soroban",
      "request": "launch",
      "contractPath": "${workspaceFolder}/target/wasm32-unknown-unknown/release/hello_world.wasm",
      "snapshotPath": "${workspaceFolder}/snapshot.json",
      "entrypoint": "increment",
      "args": [],
      "trace": false
    }
  ]
}
```

Adjust these fields for your project:

- `contractPath`: compiled contract you want to debug.
- `entrypoint`: exported Soroban function to invoke.
- `args`: JSON-compatible argument list passed to that entrypoint.
- `binaryPath`: add this only when the adapter cannot find `soroban-debug` on your `PATH`, for example when you want VS Code to use a specific local build of the CLI.

`.soroban-debug.toml` complements `launch.json`; use the TOML file for shared debugger defaults such as breakpoints or output behavior, and `launch.json` for VS Code session wiring.

## 3. Validate the launch configuration

Before starting a session, run the built-in preflight check:

1. Open the Command Palette.
2. Run `Soroban: Run Launch Preflight Check`.
3. Pick the Soroban launch configuration you just created.

Use this whenever you change `contractPath`, `binaryPath`, or argument structure. The preflight check catches invalid launch settings before the adapter starts.

## 4. Set breakpoints in Rust source

Open the Rust file that corresponds to the contract you want to debug, for example `contracts/hello_world/src/lib.rs`.

Set breakpoints in the editor gutter on executable lines such as:

- The first line inside `increment`.
- The storage write line where state changes are committed.

You can confirm the breakpoints in the **Run and Debug** panel before you launch the session.

If a breakpoint stays gray or shows as unverified:

1. Open the file where the breakpoint is set.
2. Run `Soroban: Diagnose Source Maps for Current File`.
3. Move the breakpoint to the nearest executable statement if the diagnostic reports a source-mapping gap.

## 5. Start the session and inspect state

Start the `Soroban: Debug hello_world` configuration from the **Run and Debug** view.

When execution stops at a breakpoint:

- Use `F10`, `F11`, and `Shift+F11` for stepping.
- Inspect storage and locals in the **Variables** panel.
- Review the call stack in the **Call Stack** panel.
- Watch adapter output in the **Debug Console** if you enabled `"trace": true`.

## 6. Keep the setup repeatable

Store editor-specific session settings in `.vscode/launch.json`, and keep repo-wide debugger defaults in `.soroban-debug.toml`. That split keeps the VS Code adapter configuration explicit while still giving new contributors sensible defaults when they start with the CLI.

Next steps:

- [First Debug Session](first-debug.md) for the CLI-first walkthrough.
- [Breakpoints Reference](../breakpoints.md) for source and function breakpoint behavior.
- [VS Code extension README](../../extensions/vscode/README.md) for the full launch/attach schema.
