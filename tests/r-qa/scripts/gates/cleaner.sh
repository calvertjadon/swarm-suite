#!/usr/bin/env bash
# Swarm cleaner gate — run the configured cleaner toolchain for every detected
# language; exit 0 only if every command passes.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"
swarm_run_gate cleaner
