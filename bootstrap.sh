#!/bin/sh
# One-command installer for the OMP swarm suite (github.com/calvertjadon/swarm-suite).
# Downloads the repo tarball, installs to $SWARM_SUITE_DIR
# (default ~/.local/share/swarm-suite), and runs install.sh.
set -eu

REPO=calvertjadon/swarm-suite
REF=main
DEST="${SWARM_SUITE_DIR:-$HOME/.local/share/swarm-suite}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "swarm-suite: downloading $REPO@$REF ..."
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" -o "$tmp/suite.tar.gz"

top="$(tar tzf "$tmp/suite.tar.gz" | head -1 | cut -d/ -f1)"
tar xzf "$tmp/suite.tar.gz" -C "$tmp"

mkdir -p "$(dirname "$DEST")"
if [ -e "$DEST" ]; then
  backup="$DEST.bak.$(date +%Y%m%d%H%M%S)"
  mv "$DEST" "$backup"
  echo "swarm-suite: existing install moved to $backup"
fi
mv "$tmp/$top" "$DEST"

cd "$DEST"
bash install.sh

echo
echo "swarm-suite installed to $DEST"
echo "Verify:   bash $DEST/tests/gates-test.sh   (expect 30 pass, 0 fail)"
echo "Onboard:  cd <repo> && git init && /swarm init"
