#!/usr/bin/env bash
# Shared helpers for swarm gate dispatchers (scripts/gates/).
#
# <command> is a single-line double-quoted YAML scalar; the standard YAML
# escapes \\ and \" are decoded left-to-right and all other backslashes
# are literal.  Each gate runs the resolved command for every detected
# language with `bash -c` from the repository root; the command's exit
# code is the verdict (0 = pass, every language's command must pass).  A
# missing `<lang>.<role>` cell fails the gate with a "run /swarm init"
# message.

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

swarm_root() {
  if git -C "$GATE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$GATE_DIR" rev-parse --show-toplevel
  else
    (cd "$GATE_DIR/../.." && pwd)
  fi
}

swarm_detect_langs() {
  local root found=""
  root="$(swarm_root)"
  [[ -f "$root/pyproject.toml" || -f "$root/setup.py" || -f "$root/setup.cfg" ]] && found="$found py"
  compgen -G "$root"/requirements*.txt >/dev/null 2>&1 && found="$found py"
  [[ -f "$root/go.mod" ]] && found="$found go"
  [[ -f "$root/package.json" ]] && found="$found ts"
  # shellcheck disable=SC2086
  printf '%s\n' $found | sed '/^$/d' | sort -u
}

swarm_resolve_cmd() { # $1=lang $2=role — prints the command; empty if absent
  local lang="$1" role="$2" file cmd
  for file in "$GATE_DIR/tools.yml" "$GATE_DIR/tools.defaults.yml"; do
    [[ -f "$file" ]] || continue
    cmd="$(awk -v lang="$lang" -v role="$role" '
      /^[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*(#.*)?$/ {
        cur = $0
        sub(/[[:space:]]*:.*$/, "", cur)
        next
      }
      /^  [A-Za-z0-9_-]+[[:space:]]*:/ {
        r = $0
        sub(/^  /, "", r)
        sub(/[[:space:]]*:.*$/, "", r)
        if (cur == lang && r == role) {
          v = $0
          sub(/^[^:]*:[[:space:]]*/, "", v)
          if (v ~ /^"/) {
            sub(/^"/, "", v)
            if (v ~ /"([[:space:]]*#.*)?$/) sub(/"([[:space:]]*#.*)?$/, "", v)
          } else {
            sub(/[[:space:]]*#.*$/, "", v)
            sub(/[[:space:]]+$/, "", v)
          }
          gsub(/\\\\/, "\034", v)
          gsub(/\\"/, "\"", v)
          gsub(/\034/, "\\", v)
          print v
        }
      }' "$file")"
    [[ -n "$cmd" ]] && { printf '%s\n' "$cmd"; return 0; }
  done
  return 1
}

swarm_run_gate() { # $1=role — exit 0 iff every resolved command passed
  local role="$1" root lang langs cmd failures=0 ran=0
  langs="$(swarm_detect_langs)"
  if [[ -z "$langs" ]]; then
    echo "swarm gate '$role': no supported language detected (markers: pyproject.toml|setup.py|setup.cfg|requirements*.txt, go.mod, package.json)" >&2
    return 1
  fi
  root="$(swarm_root)"
  cd "$root" || return 1
  for lang in $langs; do
    if ! cmd="$(swarm_resolve_cmd "$lang" "$role")" || [[ -z "$cmd" ]]; then
      echo "swarm gate '$role': no '$lang.$role' tool configured — run /swarm init to choose the $lang $role tool" >&2
      failures=$((failures + 1))
      continue
    fi
    ran=$((ran + 1))
    echo "== swarm gate '$role' [$lang]: $cmd" >&2
    if ! bash -c "$cmd"; then
      echo "swarm gate '$role' [$lang] FAILED: $cmd" >&2
      failures=$((failures + 1))
    fi
  done
  [[ "$ran" -eq 0 ]] && return 1
  return "$failures"
}
