#!/usr/bin/env bash
# Install the swarm gauntlet suite into the user-level OMP agent directory.
# Idempotent: existing differing files are backed up (timestamped .backup).
# Modeled on omp-dev-starter's install-global.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"

mkdir -p "$DEST/agents" "$DEST/commands" \
         "$DEST/skills/swarm/templates/gates" \
         "$DEST/skills/swarm/templates/tools"

copy_file() { # copy_file <src> <dst>
  local src="$1" dst="$2"
  if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
    local bak="$dst.backup.$(date +%Y%m%d%H%M%S)"
    cp "$dst" "$bak"
    echo "Backed up existing $dst -> $bak"
  fi
  cp "$src" "$dst"
  echo "Installed $dst"
}

for f in "$ROOT"/global/agents/*.md; do
  copy_file "$f" "$DEST/agents/$(basename "$f")"
done

for f in "$ROOT"/global/commands/*.md; do
  copy_file "$f" "$DEST/commands/$(basename "$f")"
done

copy_file "$ROOT/global/skills/swarm/SKILL.md" "$DEST/skills/swarm/SKILL.md"
for f in "$ROOT"/global/skills/swarm/templates/gates/*; do
  copy_file "$f" "$DEST/skills/swarm/templates/gates/$(basename "$f")"
done
for f in "$ROOT"/global/skills/swarm/templates/tools/*; do
  copy_file "$f" "$DEST/skills/swarm/templates/tools/$(basename "$f")"
done
chmod +x "$DEST"/skills/swarm/templates/gates/*.sh \
         "$DEST"/skills/swarm/templates/tools/crap.py

# Enable isolated coder workspaces (idempotent; needs the omp CLI on PATH).
if command -v omp >/dev/null 2>&1; then
  omp config set task.isolation.mode auto
  echo "Set task.isolation.mode = auto"
else
  echo "NOTE: omp not on PATH — add to ~/.omp/agent/config.yml:"
  printf 'task:\n  isolation:\n    mode: auto\n'
fi

echo
echo "Swarm suite installed."
echo "Restart any running OMP session before testing discovery."
echo "Per-repo onboarding:  cd <repo> && /swarm init   (see README.md)"
