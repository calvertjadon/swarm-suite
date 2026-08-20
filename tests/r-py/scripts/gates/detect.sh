#!/usr/bin/env bash
# Swarm language detector — emits one language code per line (py, go, ts)
# for the detected markers: pyproject.toml|setup.py|setup.cfg|requirements*.txt,
# go.mod, package.json.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
swarm_detect_langs
