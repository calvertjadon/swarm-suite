#!/usr/bin/env bash
# Swarm QA gate — run every scripts/qa/*.sh check.  Fixed, language-agnostic:
# requires at least one check; exit 0 only if every check passes.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git -C "$here" rev-parse --show-toplevel >/dev/null 2>&1; then
  root="$(git -C "$here" rev-parse --show-toplevel)"
else
  root="$(cd "$here/../.." && pwd)"
fi
cd "$root" || exit 1
shopt -s nullglob
checks=(scripts/qa/*.sh)
if [[ ${#checks[@]} -eq 0 ]]; then
  echo "swarm gate 'qa': no checks under scripts/qa/ — QA must write scripts/qa/<slice>.sh with a check per acceptance criterion" >&2
  exit 1
fi
failures=0
for check in "${checks[@]}"; do
  echo "== swarm gate 'qa': $check" >&2
  if ! bash "$check"; then
    echo "swarm gate 'qa' FAILED: $check" >&2
    failures=$((failures + 1))
  fi
done
exit "$failures"
