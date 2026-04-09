#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BASE_SHA="${PR_BASE_SHA:-}"
HEAD_SHA="${PR_HEAD_SHA:-${GITHUB_SHA:-HEAD}}"

if [[ -z "$BASE_SHA" ]]; then
  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    git fetch origin "${GITHUB_BASE_REF}" --depth=1
    BASE_SHA="$(git rev-parse "origin/${GITHUB_BASE_REF}")"
  else
    echo "PR_BASE_SHA or GITHUB_BASE_REF is required" >&2
    exit 1
  fi
fi

mapfile -t commits < <(git rev-list --reverse "${BASE_SHA}..${HEAD_SHA}")
if [[ "${#commits[@]}" -ne 3 ]]; then
  echo "Expected exactly 3 commits on golden-solution, found ${#commits[@]}" >&2
  git log --oneline "${BASE_SHA}..${HEAD_SHA}" >&2
  exit 1
fi

sol_sha="${commits[0]}"
f2p_sha="${commits[1]}"
meta_sha="${commits[2]}"

sol_msg="$(git log -1 --pretty=%s "$sol_sha")"
f2p_msg="$(git log -1 --pretty=%s "$f2p_sha")"
meta_msg="$(git log -1 --pretty=%s "$meta_sha")"

[[ "$sol_msg" == \[sol\]* ]] || { echo "First commit must start with [sol]" >&2; exit 1; }
[[ "$f2p_msg" == \[f2p\]* ]] || { echo "Second commit must start with [f2p]" >&2; exit 1; }
[[ "$meta_msg" == \[meta\]* ]] || { echo "Third commit must start with [meta]" >&2; exit 1; }

if git rev-list --merges "${BASE_SHA}..${HEAD_SHA}" | grep -q .; then
  echo "Merge commits are not allowed on golden-solution" >&2
  exit 1
fi

mapfile -t sol_files < <(git diff-tree --no-commit-id --name-only -r "$sol_sha")
mapfile -t f2p_files < <(git diff-tree --no-commit-id --name-only -r "$f2p_sha")
mapfile -t meta_files < <(git diff-tree --no-commit-id --name-only -r "$meta_sha")

for file in "${sol_files[@]}"; do
  if [[ "$file" == test/* || "$file" == .helix/* ]]; then
    echo "[sol] commit must not modify tests or .helix files: $file" >&2
    exit 1
  fi
done

for file in "${f2p_files[@]}"; do
  if [[ "$file" != test/* ]]; then
    echo "[f2p] commit must only modify test files: $file" >&2
    exit 1
  fi
done

if [[ "${#meta_files[@]}" -ne 1 || "${meta_files[0]}" != ".helix/metadata.json" ]]; then
  echo "[meta] commit must only modify .helix/metadata.json" >&2
  exit 1
fi

for forbidden in .helix/Dockerfile.helix .helix/run-tests-eval.sh; do
  if printf '%s\n' "${sol_files[@]}" "${f2p_files[@]}" "${meta_files[@]}" | grep -qx "$forbidden"; then
    echo "Golden-solution commits must not modify $forbidden" >&2
    exit 1
  fi
done

problem_statement="$(jq -r '.[0].problem_statement' .helix/metadata.json)"
hints="$(jq -r '.[0].hints' .helix/metadata.json)"
fail_to_pass="$(jq -r '.[0].FAIL_TO_PASS' .helix/metadata.json)"
pass_to_pass="$(jq -r '.[0].PASS_TO_PASS' .helix/metadata.json)"

for field_name in problem_statement hints fail_to_pass pass_to_pass; do
  if [[ -z "${!field_name}" || "${!field_name}" == "null" ]]; then
    echo "Metadata field ${field_name} must be populated" >&2
    exit 1
  fi
done

base_dir="$(mktemp -d)"
sol_dir="$(mktemp -d)"

cleanup() {
  git worktree remove --force "$base_dir" >/dev/null 2>&1 || true
  git worktree remove --force "$sol_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

git worktree add --detach "$base_dir" "$BASE_SHA" >/dev/null
git worktree add --detach "$sol_dir" "$BASE_SHA" >/dev/null

(
  cd "$base_dir"
  git cherry-pick --no-commit "$f2p_sha" >/dev/null
  npm install --ignore-scripts --package-lock=false >/dev/null
  ./.helix/run-tests-eval.sh "$pass_to_pass"
  if ./.helix/run-tests-eval.sh "$fail_to_pass"; then
    echo "FAIL_TO_PASS tests unexpectedly passed on the base commit" >&2
    exit 1
  fi
)

(
  cd "$sol_dir"
  git cherry-pick --no-commit "$sol_sha" >/dev/null
  git cherry-pick --no-commit "$f2p_sha" >/dev/null
  npm install --ignore-scripts --package-lock=false >/dev/null
  ./.helix/run-tests-eval.sh "$pass_to_pass"
  ./.helix/run-tests-eval.sh "$fail_to_pass"
)
