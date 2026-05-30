# Remote Debugging Capability Negotiation

## Overview

When a client connects to a remote Soroban debugger server, both sides now exchange capability metadata during the handshake. This allows incompatibilities to be detected **at connection time** rather than later when operations are attempted.

## How It Works

### Connection Handshake Sequence

```
Client                                    Server
  |                                         |
  |--- Connect (TCP) ------------------>  |
  |                                         |
  |--- Handshake Request                   |
  |    (client_name, client_version,       |
  |     protocol_version,                  |
  |     required_capabilities) -------->  |
  |                                         |
  |                                    [Validate protocol version]
  |                                    [Build server capabilities]
  |                                    [Check compatibility]
  |                                         |
  |<--- Handshake Response                 |
  |     (server_version,                   |
  |      server_capabilities,              |
  |      negotiated_features) ----------   |
  |                                         |
  |--- Authenticate (if token) -------->  |
  |                                         |
  |<--- Auth Response -------------------- |
  |                                         |
  | [Ready for operations]                 |
  |                                         |
```

## Supported Capabilities

The following capabilities can be negotiated:

| Capability | Description |
|---|---|
| `conditional_breakpoints` | Supports conditional and hit-count breakpoints |
| `source_breakpoints` | Supports source-level (DWARF) breakpoints via `ResolveSourceBreakpoints` |
| `evaluate` | Supports the `Evaluate` request for expression inspection |
| `tls` | Supports TLS-encrypted connections |
| `token_auth` | Supports token-based authentication |
| `session_lifecycle` | Supports heartbeat/idle-timeout negotiation |
| `repeat_execution` | Supports repeat execution via `repeat_count` |
| `symbolic_analysis` | Supports the symbolic analysis command |
| `snapshot_loading` | Supports loading network snapshots via `LoadSnapshot` |
| `dynamic_trace_events` | Supports the `GetEvents` / DynamicTrace command |

## Error Scenarios

### Scenario 1: Client Requires Feature Server Doesn't Support

**Client declares:** `required_capabilities: { evaluate: true, snapshot_loading: true }`

**Server supports:** `{ evaluate: true, snapshot_loading: false, ... }`

**Result:** Connection rejected at handshake with error:
```
Server is missing required capabilities [snapshot_loading]. 
Upgrade the server or disable these features on the client.
```

### Scenario 2: Both Support All Required Features

**Client declares:** `required_capabilities: { evaluate: true }`

**Server supports:** `{ evaluate: true, ... }`

**Result:** Connection succeeds; operations proceed normally

## Backward Compatibility

- **Old clients connecting to new servers:** If the client doesn't send `required_capabilities`, the server treats it as having no requirements and accepts the connection.
- **New clients connecting to old servers:** If the server doesn't advertise capabilities, the client treats it as supporting nothing optional.

## Usage Examples

### Rust Client

```rust
use soroban_debugger::client::RemoteClient;
use soroban_debugger::server::protocol::ServerCapabilities;

// Create a client that requires specific capabilities
let mut config = RemoteClientConfig::default();
config.required_capabilities = Some(ServerCapabilities {
    evaluate: true,
    snapshot_loading: true,
    ..Default::default()
});

let mut client = RemoteClient::connect_with_config(
    "127.0.0.1:8000",
    None,
    config,
)?;

// If server doesn't support evaluate, this fails at handshake
```

## Troubleshooting

### "Server is missing required capabilities"

**Cause:** The server build doesn't support a feature the client needs.

**Solutions:**
1. Upgrade the server to a newer version that supports the feature
2. Disable the feature requirement on the client side
3. Check the server's capability list to see what it does support
