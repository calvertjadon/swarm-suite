# swarm-suite — OMP Swarm Gauntlet bundle

Role-separated, deterministic-gated implementation pipeline for OMP:
specifier → coder → cleaner → (architect) → hardener → QA, with human gates
at spec approval and final acceptance, and tool gates everywhere else
(Cucumber acceptance, unit tests, complexity ≤ 6, coverage ≥ 90%,
0 surviving mutants, dependency rules). One bundle installs on any machine
that has `omp`; each repo onboards itself with `/swarm init`.

## Layout

| Path | Installs to | Purpose |
|---|---|---|
| `global/agents/*.md` | `~/.omp/agent/agents/` | Six role agents (specifier, coder, cleaner, architect, hardener, qa) |
| `global/skills/swarm/` | `~/.omp/agent/skills/swarm/` | Orchestrator protocol + per-repo gate machinery templates |
| `global/commands/*.md` | `~/.omp/agent/commands/` | `/swarm` and `/swarm-init` slash commands |
| `install.sh` | — | Copies the above with backups; sets `task.isolation.mode=auto` |
| `examples/` | — | Validated toolchain cells: `go-tools.yml`, `golangci-depguard.yml` (v1), `importlinter.contract` |
| `tests/gates-test.sh` | — | 30-assertion unit suite for the gate machinery (detect/resolve/dispatch/qa/crap.py) |

## Install

```bash
bash install.sh          # idempotent; differing existing files are backed up
# then restart any running omp session
```

## Verify

```bash
bash tests/gates-test.sh                    # tests the copy installed in ~/.omp/agent
SWARM_TPL=$PWD/global/skills/swarm/templates bash tests/gates-test.sh   # tests this bundle directly
```

Both should end `result: 30 pass, 0 fail`.

## Onboard a project (per repo, HITL)

```bash
cd <repo> && git init        # required for parallel isolated coders
/swarm init                  # detects languages, asks tool choices per language, writes scripts/gates/tools.yml
```

`/swarm init` also validates each chosen command against the installed tool
version and prints exact install commands for anything missing. Validated
facts this suite already encodes (do not rediscover them):

- **gocyclo** takes files/dirs, not `./...` — use `gocyclo -over 6 .` and
  capture output with `|| true` (it exits 1 when offenders exist, which
  short-circuits `&&` chains).
- **go-mutesting** is broken on Go ≥ 1.2x (go/types panic, exit 0). Use
  `gremlins unleash --threshold-efficacy 100 ./...` (exits nonzero when any
  mutant lives). `go install github.com/go-gremlins/gremlins/cmd/gremlins@latest`.
- **gocuke** module path is `github.com/regen-network/gocuke` (not
  `regennetwork/…`) — a test library, no CLI; the coder adds it via `go get`.
- **mutmut ≥ 3** dropped `result-ids` — zero-survivor assertion is
  `mutmut run && out="$(mutmut results --all false)" && [ -z "$out" ]`.
- **import-linter** has no `python -m` entry point — use `import-linter lint`,
  and add `include_external_packages = True` to forbid external modules.
- **golangci-lint v1** expects the v1 config shape (see
  `examples/golangci-depguard.yml`); `version: "2"` configs need v2.x.
- **behave** exits 1 on an empty `features/` dir — quick mode needs a
  scenario-less `features/quick.feature`.
- GOPATH must differ from GOROOT (`go env -w GOPATH=…`) or `go install`
  pollutes the toolchain tree.

## Updating

Edit files in this repo, re-run `install.sh`, restart omp. Project-level
overrides still win per OMP precedence (`.omp/agents/`, `.omp/commands/`).
