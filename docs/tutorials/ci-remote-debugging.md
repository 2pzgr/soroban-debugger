# Tutorial: Remote Debugging in CI

This tutorial walks you through setting up and using remote debugging for a Soroban contract running in a Continuous Integration (CI) environment. This is the typical DevOps use case for debugging failing CI tests where a local SSH tunnel isn't feasible.

## Prerequisites

- A GitHub Actions workflow (or similar CI) running tests.
- `soroban-debug` installed both locally and in the CI environment.
- The contract WASM artifact you want to debug.
- A secure way to access the CI runner's network, such as Tailscale, Ngrok, or an exposed port (only if heavily protected).

## Step 1: Start the Debug Server in CI

Configure your CI pipeline to start the debug server before running the failing tests or pause the build upon failure to allow you to attach. It is critical to protect the server with an authentication token to prevent unauthorized access.

Add the following step to your CI workflow (e.g., in `.github/workflows/test.yml`):

```yaml
steps:
  - name: Start Debug Server
    run: |
      # Use a secure, randomly generated token from secrets
      soroban-debug server \
        --host 0.0.0.0 \
        --port 9229 \
        --token "${{ secrets.DEBUG_TOKEN }}" &
      echo $! > server.pid
      # Give the server a moment to start
      sleep 2
```

> **Warning:** Binding to `0.0.0.0` exposes the port to all interfaces on the runner. This should only be done if the CI environment's ingress is restricted, or if used in conjunction with TLS transport hardening. Never expose unprotected debugging ports to the public internet.

## Step 2: Configure the Remote Client

On your local workstation, configure the remote client to connect to the CI environment. You'll need the CI runner's IP address or hostname. 

Assuming the runner is reachable at `ci-runner.internal.example.com` on your corporate VPN:

```bash
soroban-debug remote \
  --remote ci-runner.internal.example.com:9229 \
  --token "$SOROBAN_DEBUG_TOKEN" \
  --contract ./target/wasm32-unknown-unknown/release/contract.wasm \
  --function failing_test_function \
  --args '[]'
```

Make sure your local `$SOROBAN_DEBUG_TOKEN` environment variable strictly matches the one stored in your CI secrets.

## Step 3: Connect and Debug

When the remote client connects, you can use the typical debugger commands to inspect the state and pinpoint the issue:

1. **Set Breakpoints:** Use `break` to pause execution at critical locations before the failure.
2. **Step Through Code:** Use `step`, `next`, and `finish` to trace execution path.
3. **Inspect State:** Use `print` to view variables and `storage` to inspect the ledger data.
4. **Identify the Cause:** Observe the conditions that lead to the test failure (e.g., an unexpected panic or incorrect return value).

## Step 4: Graceful Shutdown

Once the debug session finishes, the CI pipeline should gracefully shut down the debug server so the job can complete cleanly and release runner resources.

Ensure your workflow has a cleanup step:

```yaml
  - name: Cleanup Debug Server
    if: always()
    run: |
      [ -f server.pid ] && kill $(cat server.pid) || true
      wait
```

## Next Steps

- Review the [Remote Debugging Guide](../remote-debugging.md) for deeper details on TLS and transport hardening, especially if your CI runners operate on untrusted networks.
- If you encounter connection issues, refer to [Remote Troubleshooting](../remote-troubleshooting.md).
