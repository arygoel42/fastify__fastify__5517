#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export CI="${CI:-1}"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

usage_error() {
  printf '%s\n' "$1" >&2
  printf '%s\n' "Usage: ./.helix/run-tests-eval.sh [comma-separated repo-relative test files]" >&2
}

run_import_smoke_test() {
  ./node_modules/.bin/tsc test/types/import.ts --esModuleInterop --noEmit
}

run_default_suite() {
  # The full upstream tsd matrix drifts against today's dependency resolution on this
  # historical base snapshot. Keep the default Helix smoke run focused on the route/type
  # provider coverage that this task exercises, and rely on targeted metadata lists for
  # the full F2P/P2P validation paths.
  run_targeted_suite "test/types/route.test-d.ts,test/types/type-provider.test-d.ts"
}

run_targeted_suite() {
  local raw_list="$1"
  if [[ -z "$raw_list" ]]; then
    usage_error "Error: empty test file list provided. Omit the argument to run the default suite."
    return 1
  fi

  local raw_paths=()
  IFS=',' read -r -a raw_paths <<< "$raw_list"

  if [[ ${#raw_paths[@]} -eq 0 ]]; then
    usage_error "Error: no test files were parsed from the provided list."
    return 1
  fi

  local validated_paths=()
  local raw_path trimmed_path
  for raw_path in "${raw_paths[@]}"; do
    trimmed_path="$(trim "$raw_path")"
    if [[ -z "$trimmed_path" ]]; then
      usage_error "Error: empty test file entry detected in '$raw_list'."
      return 1
    fi
    if [[ "$trimmed_path" = /* ]]; then
      usage_error "Error: absolute paths are not allowed: $trimmed_path"
      return 1
    fi
    if [[ "$trimmed_path" != test/types/*.test-d.ts ]]; then
      usage_error "Error: targeted tests must stay within test/types and end with .test-d.ts: $trimmed_path"
      return 1
    fi
    if [[ ! -f "$trimmed_path" ]]; then
      usage_error "Error: test file not found: $trimmed_path"
      return 1
    fi
    validated_paths+=("$trimmed_path")
  done

  run_import_smoke_test

  local test_file
  for test_file in "${validated_paths[@]}"; do
    ./node_modules/.bin/tsd --files "$test_file"
  done
}

case "$#" in
  0)
    run_default_suite
    ;;
  1)
    run_targeted_suite "$1"
    ;;
  *)
    usage_error "Error: expected zero arguments or one comma-separated file list."
    exit 1
    ;;
esac
