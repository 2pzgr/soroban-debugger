
```markdown
# Debugging Cross-Contract Calls in Soroban

This tutorial shows how to **debug contracts that call other contracts** in Soroban.
We’ll create a simple **caller + callee** example, set breakpoints in both contracts, and inspect the call stack and event logs.

---

## 1. Directory Structure

```

examples/contracts/cross-contract/
├── callee_contract.rs as there are no example contracts
├── caller_contract.rs
└── integration_test.rs

````

---

## 2. Callee Contract

Create `examples/contracts/cross-contract/callee_contract.rs`:

```rust
#![no_std]
use soroban_sdk::{contract, contractimpl, Env};

#[contract]
pub struct CalleeContract;

#[contractimpl]
impl CalleeContract {
    // Increment a value and emit an event
    pub fn increment(env: Env, value: i32) -> i32 {
        let new_value = value + 1;
        env.events().publish("incremented", new_value);
        new_value
    }
}
````

**Notes:**

* Emits an event `"incremented"` each time the function is called.

---

## 3. Caller Contract

Create `examples/contracts/cross-contract/caller_contract.rs`:

```rust
#![no_std]
use soroban_sdk::{contract, contractimpl, Env, Address};

#[contract]
pub struct CallerContract;

#[contractimpl]
impl CallerContract {
    // Call the CalleeContract increment function
    pub fn call_increment(env: Env, callee: Address, value: i32) -> i32 {
        env.invoke_contract::<i32>(&callee, &("increment", value))
    }
}
```

**Notes:**

* Uses `invoke_contract` to call the callee contract.
* Demonstrates a cross-contract call.

---

## 4. Integration Test

Create `examples/contracts/cross-contract/integration_test.rs`:

```rust
#![cfg(test)]
use soroban_sdk::{Env, Address};
use cross_contract::{CallerContractClient, CalleeContractClient};

#[test]
fn test_cross_contract_call() {
    let env = Env::default();

    // Deploy CalleeContract
    let callee_id = env.register_contract(None, CalleeContractClient);
    let callee = Address::from_contract_id(callee_id.clone());

    // Deploy CallerContract
    let caller_id = env.register_contract(None, CallerContractClient);
    let caller = Address::from_contract_id(caller_id.clone());

    // Call Callee directly
    let result_direct = CalleeContractClient::increment(&env, &callee, 5);
    assert_eq!(result_direct, 6);

    // Call Callee via Caller
    let result_via_caller = CallerContractClient::call_increment(&env, &caller, &callee, 5);
    assert_eq!(result_via_caller, 6);

    // Verify event emitted
    let events = env.events().all();
    assert_eq!(events.len(), 2); // one for direct, one for via caller
}
```

**Notes:**

* Tests direct call vs cross-contract call.
* Verifies events are logged even across contract boundaries.

---

## 5. Debugging Steps

1. Compile the contracts:

```bash
cargo build --release
```

2. Launch the debugger on the CallerContract:

```bash
soroban-debugger examples/contracts/cross-contract/caller_contract.wasm
```

3. Set breakpoints:

```text
break caller_contract.rs:10  # Before calling callee
break callee_contract.rs:7   # Inside increment function
```

4. Step through the debugger:

```text
step        # Move to next instruction
bt          # View call stack
```

**Expected Call Stack Output:**

```
Frame 0: CallerContract::call_increment
Frame 1: CalleeContract::increment
```

---

## 6. Inspect Event Logs

Even across contract calls:

```text
Event: "incremented" = 6
Event: "incremented" = 6
```

* Events emitted in the callee are visible in the debugger.

---

## 7. Key Takeaways

* Cross-contract calls appear in the **call stack**.
* Breakpoints work in **both caller and callee**.
* Event logs from callee are observable.
* Step-by-step debugging helps trace issues in multi-contract interactions.

---

## 8. Isolating Cross-Contract Calls with `--mock`

When debugging the caller contract in isolation, you often do not want the callee contract to execute for real — either because it is not deployed locally, its side-effects interfere with the test, or you simply want to focus on the caller's logic. The `--mock` flag lets you intercept any cross-contract call and return a fixed value instead.

### Syntax

```bash
soroban-debugger <contract.wasm> --function <fn> \
  --mock "<CONTRACT_ID>.<function>=<return_value>"
```

The flag is repeatable. Each `--mock` entry specifies:

| Part | Description |
|---|---|
| `CONTRACT_ID` | The contract address whose calls you want to intercept. |
| `function` | The specific function name on that contract to mock. |
| `return_value` | The value the mock returns to the caller, expressed as a Soroban-compatible literal. |

### Example: mock the callee during caller debugging

```bash
soroban-debugger examples/contracts/cross-contract/caller_contract.wasm \
  --function call_increment \
  --mock "CALLEE_CONTRACT_ID.increment=7"
```

With this command, any call from `CallerContract` to `CalleeContract::increment` is intercepted and returns `7` immediately — the callee WASM never executes.

### Mocking multiple callees

```bash
soroban-debugger caller_contract.wasm --function call_increment \
  --mock "CONTRACT_A.increment=7" \
  --mock "CONTRACT_B.get_price=100"
```

### Mock call log

After the session completes, the debugger prints a **Mock Contract Calls** log summarising every cross-contract call observed during execution and whether it was intercepted (`MOCKED`) or passed through to the real contract (`REAL`):

```
--- Mock Contract Calls ---
1. MOCKED  CALLEE_CONTRACT_ID increment (args: [5]) -> 7
2. REAL    OTHER_CONTRACT_ID  other_fn  (args: [])  -> 42
```

This log helps you verify that mocked call sites were actually reached during the debug session.

### VS Code launch configuration

In `.vscode/launch.json`, pass mocks via the `mock` array:

```json
{
  "type": "soroban-debugger",
  "request": "launch",
  "mock": [
    "CALLEE_CONTRACT_ID.increment=7"
  ]
}
```

### When to use `--mock`

* The callee contract binary is not available locally.
* You want deterministic callee responses to reproduce a specific caller code path.
* You are writing unit-style debugging sessions focused on a single contract boundary.

For more advanced mock patterns (storage setup, event expectations), see [mock-helpers.md](mock-helpers.md).

---

## 9. Git Workflow

```bash
git checkout -b docs/tutorial-cross-contract
mkdir -p examples/contracts/cross-contract
# Add the two contracts and integration_test.rs
# Add docs/tutorials/debug-cross-contract.md
git add examples/contracts/cross-contract/*.rs docs/tutorials/debug-cross-contract.md
git commit -m "docs: add cross-contract debugging tutorial"
git push origin docs/tutorial-cross-contract
```

---

## 10. Next Steps

* Try nested cross-contract calls and watch the stack grow.
* Add more complex callee logic and test how the caller handles it.
* Combine debugging with unit tests for automated verification.

```

```
