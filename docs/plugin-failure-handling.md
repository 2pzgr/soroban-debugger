# Plugin Failure Handling

The Soroban debugger treats plugins as extensions, not as part of the trusted
execution core.

## What Counts As A Plugin Incident

The debugger currently escalates these plugin-specific incidents:

- plugin panics,
- plugin invocation timeouts.

Regular plugin-returned errors are still reported, but they do not
automatically count as crash-isolation incidents.

## What Happens On Incident

When a plugin panics or exceeds its execution budget:

1. the incident is captured and classified as a plugin-layer failure,
2. the affected plugin is disabled for the current process/session,
3. the core debugger continues running,
4. a structured incident report is emitted through logging and telemetry.

This is intentionally explicit so users are not misled into thinking that a
plugin crash means the Soroban debugger itself became unstable.

## What Happens To In-Flight Events When The Circuit Opens

Understanding what happens to the event that was being dispatched at the moment
a plugin trips the circuit breaker is important for reasoning about plugin
output and session state.

### Panics

A panic is caught synchronously inside `catch_unwind` during the current
dispatch call. The sequence is:

1. The plugin's `on_event` handler panics.
2. `catch_unwind` catches the panic before it can unwind into the debugger.
3. The panic is converted to a `PluginError::Panic` and passed to
   `record_outcome`.
4. `record_outcome` immediately sets `circuit_open = true` and
   `session_disabled = true` for that plugin.
5. An incident report is emitted and a `Panic` telemetry entry is appended to
   the current `EventContext`.
6. The dispatch loop moves on to the next plugin in the same cycle — **other
   plugins are not affected**.

The triggering event is therefore **partially processed**: the panicking plugin
did not complete its handler, but every other plugin that was registered before
it in the dispatch order already ran, and every plugin registered after it
still runs normally.

### Timeouts

Timeout detection is **post-hoc**: the plugin runs to completion and its result
is returned, but if the elapsed time exceeds the configured budget the result
is discarded and the plugin is session-disabled. The sequence is:

1. The plugin's `on_event` handler returns `Ok(())`.
2. `record_outcome` compares elapsed time against `hook_timeout`
   (default: 250 ms).
3. If elapsed > timeout, the successful return value is discarded, the plugin
   is session-disabled, and a `Timeout` incident report is emitted.
4. A `Timeout` telemetry entry is appended to the current `EventContext`.
5. The dispatch loop continues normally for all other plugins.

Because the plugin already ran to completion, any side effects it produced
(writes to its own internal state, log output, etc.) are **not rolled back**.
Only the return value is discarded.

### Subsequent Events After Disablement

Once a plugin is session-disabled, every subsequent dispatch call checks
`circuit_open || session_disabled` at the top of `run_hook_with_policy` before
doing any work:

- If the circuit is open, the hook is **skipped entirely** — `on_event` is
  never called.
- A `SkippedCircuitOpen` telemetry entry is appended to the `EventContext` so
  the skip is visible in telemetry.
- Commands and formatters from a disabled plugin return
  `PluginError::SessionDisabled` or `PluginError::CircuitOpen` immediately.

The plugin remains disabled for the lifetime of the process. There is no
automatic reset or retry within a session.

### Circuit-Open vs. Session-Disabled

The registry tracks two related but distinct flags per plugin:

| Flag | Set by | Meaning |
|------|--------|---------|
| `circuit_open` | Panic, timeout, or N consecutive failures | Invocations are skipped |
| `session_disabled` | Panic or timeout (incident-level events only) | Permanent skip for this session; shown in incident report |

A plugin can have `circuit_open = true` without `session_disabled = true` if
it accumulated enough consecutive soft failures (default threshold: 3). In that
case the circuit may reset on a subsequent success. A plugin with
`session_disabled = true` will never reset within the session regardless of
later behavior.

### Telemetry Visibility

Every skipped or failed invocation appends a `PluginTelemetryEvent` to the
`EventContext` that was passed into the dispatch call. The telemetry entry
includes:

- plugin name,
- invocation kind (`Hook`, `Command`, or `Formatter`),
- outcome (`Panic`, `Timeout`, `Failure`, `SkippedCircuitOpen`, or `Success`),
- elapsed duration in milliseconds,
- a human-readable message (the incident summary line for panics and timeouts).

This means the caller always has a record of what happened, even when the
plugin was silently skipped.

## Session Disablement

Session disablement is intentionally conservative:

- a panicking plugin is disabled immediately,
- a timed-out plugin is disabled immediately,
- subsequent invocations are skipped for the rest of the session.

This keeps the debugger usable while preventing repeated plugin failures from
polluting the debugging experience.

## Incident Report Contents

Each report includes:

- plugin name,
- plugin version when available,
- plugin library path when available,
- invocation kind (`hook`, `command`, or `formatter`),
- incident type (`panic` or `timeout`),
- action taken,
- an explicit statement that the core debugger remains available.

## Why This Matters

Plugins are powerful, but they should never blur the trust boundary.

Clear incident reporting helps users answer two separate questions quickly:

- Did the plugin fail?
- Is the core debugger still trustworthy?

The expected answer after a contained incident is:

- yes, the plugin failed,
- yes, the core debugger is still available.

## Related Documentation

- [Plugin System API Documentation](plugin-api.md) — full plugin trait reference
- [Plugin Command Namespace Policy](plugin-command-namespaces.md) — command name conflict resolution
