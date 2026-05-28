#!/usr/bin/env bash

set -euo pipefail

SOURCE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_benchmark_regressions.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bench-regression-test.XXXXXX")"

cleanup() {
    rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

setup_repo() {
    local case_root="$1"
    local repo_root="$case_root/repo"
    local bin_dir="$case_root/bin"

    mkdir -p "$repo_root/scripts" "$bin_dir"
    cp "$SOURCE_SCRIPT" "$repo_root/scripts/check_benchmark_regressions.sh"
    chmod +x "$repo_root/scripts/check_benchmark_regressions.sh"

    cat > "$repo_root/Cargo.toml" <<'EOF'
[package]
name = "bench-regression-selftest"
version = "0.1.0"
edition = "2021"

[[bench]]
name = "fake-bench"
harness = false
EOF

    git init -b main "$repo_root" >/dev/null
    git -C "$repo_root" config user.name "Codex Test"
    git -C "$repo_root" config user.email "codex@example.com"

    cat > "$repo_root/branch.txt" <<'EOF'
main
EOF
    git -C "$repo_root" add Cargo.toml branch.txt scripts/check_benchmark_regressions.sh
    git -C "$repo_root" commit -m "main branch" >/dev/null

    git -C "$repo_root" checkout -b feature >/dev/null
    cat > "$repo_root/branch.txt" <<'EOF'
feature
EOF
    git -C "$repo_root" add branch.txt
    git -C "$repo_root" commit -m "feature branch" >/dev/null

    printf '%s\n' "$repo_root|$bin_dir"
}

write_fake_cargo() {
    local bin_dir="$1"
    local mode="$2"

    cat > "$bin_dir/cargo" <<EOF
#!/usr/bin/env bash
set -euo pipefail

branch_value="\$(cat branch.txt)"

if [ "\$1" = "bench" ]; then
    printf 'cargo-bench|%s|%s|%s\\n' "\$PWD|\$branch_value" "\$CARGO_TARGET_DIR" "\$*" >> "\$LOG_FILE"
    if [ "${mode}" = "fail-base" ] && [ "\$branch_value" = "main" ]; then
        echo "simulated baseline benchmark failure" >&2
        exit 42
    fi
    mkdir -p "\$CARGO_TARGET_DIR/criterion/fake"
    printf '%s\\n' "\$branch_value" > "\$CARGO_TARGET_DIR/criterion/fake/source.txt"
    exit 0
fi

if [ "\$1" = "run" ]; then
    all_args="\$*"
    shift
    cmd=""
    criterion=""
    out=""
    baseline=""
    current=""
    while [ "\$#" -gt 0 ]; do
        arg="\$1"
        shift
        case "\$arg" in
            record|compare)
                cmd="\$arg"
                ;;
            --criterion)
                criterion="\${1:-}"
                [ "\$#" -gt 0 ] && shift
                ;;
            --out)
                out="\${1:-}"
                [ "\$#" -gt 0 ] && shift
                ;;
            --baseline)
                baseline="\${1:-}"
                [ "\$#" -gt 0 ] && shift
                ;;
            --current)
                current="\${1:-}"
                [ "\$#" -gt 0 ] && shift
                ;;
        esac
    done

    if [ "\$cmd" = "record" ]; then
        printf 'cargo-record|%s|%s|%s|%s\\n' "\$PWD|\$branch_value" "\$criterion" "\$out" "\$all_args" >> "\$LOG_FILE"
        printf '{"benchmarks":[{"id":"fake","mean":1.0}],"source":"%s"}\n' "\$branch_value" > "\$out"
        exit 0
    fi

    if [ "\$cmd" = "compare" ]; then
        printf 'cargo-compare|%s|%s|%s|%s\\n' "\$PWD|\$branch_value" "\$baseline" "\$current" "\$all_args" >> "\$LOG_FILE"
        test -f "\$baseline"
        test -f "\$current"
        echo "comparison ok"
        exit 0
    fi
fi

echo "unexpected cargo invocation: \$*" >&2
exit 1
EOF
    chmod +x "$bin_dir/cargo"
}

run_success_case() {
    local case_root="$TEST_ROOT/success"
    local paths
    local repo_root
    local bin_dir
    local log_file="$case_root/invocations.log"

    paths="$(setup_repo "$case_root")"
    repo_root="${paths%|*}"
    bin_dir="${paths#*|}"

    write_fake_cargo "$bin_dir" "pass"
    LOG_FILE="$log_file" PATH="$bin_dir:$PATH" bash "$repo_root/scripts/check_benchmark_regressions.sh" >/dev/null

    if [ "$(git -C "$repo_root" branch --show-current)" != "feature" ]; then
        echo "expected to remain on feature branch" >&2
        exit 1
    fi

    if ! grep -Eq "cargo-bench\\|$repo_root\\|feature\\|.*/current-target\\|" "$log_file"; then
        echo "expected current benchmark bench run in feature checkout" >&2
        cat "$log_file" >&2
        exit 1
    fi

    if ! grep -Eq "cargo-bench\\|.*/baseline-worktree\\|main\\|.*/baseline-target\\|" "$log_file"; then
        echo "expected baseline benchmark bench run in detached worktree" >&2
        cat "$log_file" >&2
        exit 1
    fi

    if ! grep -Eq "cargo-record\\|$repo_root\\|feature\\|.*/current-target/criterion\\|.*/current\\.json\\|" "$log_file"; then
        echo "expected current record command in feature checkout" >&2
        cat "$log_file" >&2
        exit 1
    fi

    if ! grep -Eq "cargo-record\\|.*/baseline-worktree\\|main\\|.*/baseline-target/criterion\\|.*/baseline\\.json\\|" "$log_file"; then
        echo "expected baseline record command in detached worktree" >&2
        cat "$log_file" >&2
        exit 1
    fi

    if ! grep -Eq "cargo-compare\\|$repo_root\\|feature\\|.*/baseline\\.json\\|.*/current\\.json\\|" "$log_file"; then
        echo "expected compare command to run in feature checkout" >&2
        cat "$log_file" >&2
        exit 1
    fi
}

run_failure_cleanup_case() {
    local case_root="$TEST_ROOT/failure"
    local paths
    local repo_root
    local bin_dir
    local output_file="$case_root/output.log"
    local status=0
    local worktree_path

    paths="$(setup_repo "$case_root")"
    repo_root="${paths%|*}"
    bin_dir="${paths#*|}"

    write_fake_cargo "$bin_dir" "fail-base"
    set +e
    LOG_FILE="$case_root/invocations.log" PATH="$bin_dir:$PATH" bash "$repo_root/scripts/check_benchmark_regressions.sh" >"$output_file" 2>&1
    status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        echo "expected injected baseline benchmark failure" >&2
        cat "$output_file" >&2
        exit 1
    fi

    if ! grep -Fq "[bench-regression] cleanup start" "$output_file"; then
        echo "expected cleanup telemetry on failure" >&2
        cat "$output_file" >&2
        exit 1
    fi

    if ! grep -Fq "[bench-regression] worktree state" "$output_file"; then
        echo "expected worktree state telemetry on failure" >&2
        cat "$output_file" >&2
        exit 1
    fi

    worktree_path="$(grep -Eo '\[bench-regression\] worktree path: .*baseline-worktree' "$output_file" | sed 's/^\[bench-regression\] worktree path: //;q')"
    if [ -z "$worktree_path" ]; then
        echo "expected cleanup telemetry to include worktree path" >&2
        cat "$output_file" >&2
        exit 1
    fi

    if [ -d "$worktree_path" ]; then
        echo "expected failing case cleanup to remove worktree path" >&2
        cat "$output_file" >&2
        exit 1
    fi
}

run_success_case
run_failure_cleanup_case

echo "benchmark regression script validates isolated worktree usage and cleanup telemetry"
