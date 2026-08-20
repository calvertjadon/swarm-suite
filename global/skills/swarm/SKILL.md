---
name: swarm
description: "Run a request through the role-agent gauntlet (specifier → coder → cleaner → architect → hardener → QA) with deterministic quality gates (Cucumber acceptance, tests, complexity, coverage, mutation, dependency rules) per stage. Trigger when the user says swarm, gauntlet, or wants multi-agent quality-gated implementation."
---

# Swarm Gauntlet — orchestrator protocol

You (the main session) run a request through role-separated agents:
specifier → coder → cleaner → (architect, full only) → hardener → QA.
Every stage after the specifier is gated by a deterministic tool script —
`scripts/gates/<role>.sh` — whose exit code is the verdict; **stages never
advance on a failing gate**. The specifier's gate is human approval; the
run's end is a second human gate. This file is the orchestrator's only
source of truth.

## Pipelines

- `quick` — coder → cleaner (no feature/spec/BDD artifacts).
- `standard` (default) — specifier → coder → cleaner → hardener → QA.
- `full` — standard with architect between cleaner and hardener.

The first token of the request selects the pipeline (`/swarm full <request>`);
anything else means standard. Strip the token before decomposing the request.

## File locations

- Role agents: `~/.omp/agent/agents/{specifier,coder,cleaner,architect,hardener,qa}.md`
  (project `.omp/agents/<name>.md` overrides by omp first-wins precedence).
- Gate machinery template (copy into the repo, do not edit here):
  `~/.omp/agent/skills/swarm/templates/gates/{detect.sh,lib.sh,coder.sh,cleaner.sh,architect.sh,hardener.sh,qa.sh,tools.defaults.yml}`
  and `~/.omp/agent/skills/swarm/templates/tools/crap.py`
  (also reachable via `skill://swarm/templates/...`).
- Per project: `<repo>/scripts/gates/` + `<repo>/tools/crap.py`.
- Per slice artifacts: `features/<slice>.feature`, `specs/<slice>.md`,
  `specs/<slice>.architecture.md` (full), `scripts/qa/<slice>.sh`.

## Language detection

`bash scripts/gates/detect.sh` emits one line per detected language:
`py` (pyproject.toml|setup.py|setup.cfg|requirements*.txt), `go` (go.mod),
`ts` (package.json). Repos may emit several.

## Gate dispatcher contract

`scripts/gates/<role>.sh` resolves, for each detected language, the command in
`scripts/gates/tools.yml[<lang>][<role>]` (fallback: `tools.defaults.yml`), runs
each with `bash -c` from the repo root, and exits 0 only if **all** pass.
`qa.sh` is fixed and language-agnostic: runs every `scripts/qa/*.sh`; an empty
`scripts/qa/` fails. A missing cell makes the gate exit nonzero with
`run /swarm init to choose the <lang> <role> tool` on stderr.

## Onboarding (HITL) — on `/swarm init`, and before any run that needs it

Run onboarding before the first gauntlet run whenever `scripts/gates/tools.yml`
is missing a cell for any detected language. Steps:

1. Ensure the machinery exists: if `scripts/gates/` is absent, copy it from
   the template (above) — `mkdir -p scripts/gates tools`, copy every template
   file into `scripts/gates/` and `templates/tools/crap.py` to `tools/crap.py`,
   `chmod +x scripts/gates/*.sh`. (Re-copying is idempotent; never overwrite
   an existing `tools.yml`.) Also gitignore the tools' artifacts so isolated
   coders' patches stay clean: `.pytest_cache/`, `.coverage`,
   `.mutmut-cache`, `mutants/`, `htmlcov/`, `__pycache__/`.
2. `bash scripts/gates/detect.sh`. No languages ⇒ report the supported
   markers and stop.
3. For every detected language and every role in `coder, cleaner, architect,
   hardener` whose `tools.yml` cell is missing, `ask` ONE question per
   (language, role): question "Which <lang> <role> tool?", each option's
   label = tool name, description = the exact command that will be written to
   `tools.yml` (plus any config-file caveat, e.g. stryker thresholds).
   `recommended` = the index of the `tools.defaults.yml` cell for that
   (lang, role). Always add a last option labeled "None — always passes"
   with command `true`, so the human can defer a concern.
   Alternatives worth offering when different from the default:

   | (lang, role) | default | alternative command |
   |---|---|---|
   | py coder | `python3 -m pytest && python3 -m behave features/` | `python3 -m pytest` (pytest-bdd; needs `bdd_features_base_dir = features` in pyproject) |
   | py cleaner | defaults cell | same cell with `python3 -m radon cc app --min B` instead of crap.py |
| py architect | defaults cell | `import-linter lint` (needs a `.importlinter` contract; add `include_external_packages = True` to forbid external modules) |
   | go coder | `go test ./... && go test ./features/` | same command, gocuke instead of godog for steps |
   | go cleaner | defaults cell (`gocyclo -over 6 .` — takes files/dirs, NOT `./...`; `-over N` exits 1 when offenders exist) | legacy projects: bar 6 on changed files — `out="$(files=$(git diff --name-only HEAD --diff-filter=ACMR | grep '\\.go$'); [ -n "$files" ] && gocyclo -over 6 $files 2>&1)" && [ -z "$out" ]` instead of the gocyclo leg; or `golangci-lint run` |
   | go architect | defaults cell | `golangci-lint run` (depguard config) |
   | go hardener | `gremlins unleash --threshold-efficacy 100 ./...` (exits nonzero when any mutant lives; uncovered mutants excluded from efficacy) | `go-mutesting ./...` — broken on Go ≥ 1.2x (go/types panic, exit 0); only if a working fork exists |

   Go/TS defaults are seed values: at first Go/TS onboarding, validate the
   installed tool's flags against the exact command shown before the human
   approves it (this caught gocyclo rejecting `./...` with exit 0 and
   go-mutesting crashing on Go 1.25). For stryker, remind the human to set
   `thresholds: { high: 100, low: 100, break: 100 }` in `stryker.config.mjs`.
4. Write `scripts/gates/tools.yml` from the answers: two-level YAML —
   `<lang>:` then two-space-indented `  <role>: "<command>"` lines. Keep
   every existing cell; write new cells for the answered (lang, role) pairs.
   Escape rule for values: replace `\` with `\\`, then `"` with `\"` (the
   gate parser decodes `\\` and `\"` left to right; other backslashes are
   literal). Write the `true` command for "None" answers.
5. PATH check per chosen command: strip a leading `!`, take the first token;
   `python3 -m X` ⇒ probe `python3 -m X --version`; `npx X` ⇒ probe
   `npx --no-install X --version`; otherwise `command -v <token>`. For every
   missing tool print its exact install command (table below) and **stop** —
   installation is the human's job. Tell them to re-run `/swarm init` (or the
   same `/swarm` request) afterwards.
6. If the project is not a git repository, warn that parallel isolated coders
  need one (`git init`); onboarding still works. Runs will fall back to
   serial coders until it exists.

Install commands for missing tools:

- py: `python3 -m pip install behave pytest pytest-cov mutmut`
  (`radon`, `import-linter`, `pytest-bdd` likewise via `python3 -m pip install <name>`)
- go: `go install github.com/fzipp/gocyclo/cmd/gocyclo@latest`,
  `go install github.com/cucumber/godog/cmd/godog@latest`,
  `go get github.com/regen-network/gocuke` (test library, no CLI; used via go test),
  `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`,
  `go install github.com/zimmski/go-mutesting/cmd/go-mutesting@latest`,
  `go install github.com/go-gremlins/gremlins/cmd/gremlins@latest`
- ts: `npm install --save-dev jest @cucumber/cucumber`,
  `npm install --save-dev eslint`, `npm install --save-dev dependency-cruiser`,
  `npm install --save-dev vitest @vitest/coverage-v8`, `npm install --save-dev nyc`,
  `npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner`

## Slice decomposition

Decompose the request into 1+ independent slices named `slice-1`, `slice-2`,
…. Each slice runs the pipeline. Shared project background (conventions,
paths, constraints) goes into every `task` batch's `context`.

## Spawn parameters

Task items use `name: "<Role>-<slice>"`, `agent` per stage, `schemaMode`
defaults to permissive. Per-stage `outputSchema` (JSON Schema):

- specifier:
  `{"type":"object","required":["stage","featurePath","specPath","criteriaCount","summary"],"properties":{"stage":{"type":"string"},"featurePath":{"type":"string"},"specPath":{"type":"string"},"criteriaCount":{"type":"integer"},"summary":{"type":"string"}}}`
- coder / cleaner / hardener:
  `{"type":"object","required":["stage","gate","gateOutput","summary"],"properties":{"stage":{"type":"string"},"gate":{"enum":["pass","fail","missing"]},"gateOutput":{"type":"string"},"summary":{"type":"string"},"changedFiles":{"type":"array","items":{"type":"string"}}}}`
- architect: same plus optional `reportPath` (string).
- qa: same as coder minus `changedFiles`, plus optional `qaScript` (string).

If structured output is invalid, fall back to `agent://<id>` text for the
verdict and gate output.

## Stage protocols

### Specifier (standard/full)

- One `task` batch, one item per slice, `agent: "specifier"`,
  `isolated: false`. Task text: the slice request, the slice name, and the
  project root, ending with: "Write features/<slice>.feature (each scenario
  tagged @AC-n) and specs/<slice>.md (QA steps labeled AC-n)."
- Await completion; then READ every `features/<slice>.feature` yourself.
- Human gate: one `ask` question per slice, presenting that slice's tagged
  scenarios (tag + scenario name + steps). Options: "Approve" (recommended),
  "Request changes" (the user describes edits), "Stop the run". Any
  "Request changes" respawns only that slice's specifier with the feedback
  (max 2 revision rounds total); then present the `ask` again regardless of
  round count. "Stop" aborts the whole run.

### Coder (all pipelines)

- One `task` batch, one item per slice, `agent: "coder"`,
  **`isolated: true`** (parallel coders; needs `task.isolation.mode` != none
  and a git repo). Task text: (quick mode: the raw slice request plus "no
  feature or step definitions apply; the gate command is fixed, leave its
  BDD leg green — e.g. add a `features/quick.feature` with only a `Feature:`
  line and no scenarios if the runner needs a feature file") or
  (standard/full: `features/<slice>.feature` path, `specs/<slice>.md` path,
  and the project root), plus the project root and the gate contract
  reminder.
- After the batch completes, verify on the parent tree:
  `bash ./scripts/gates/coder.sh`. If nonzero:
  1. Non-isolated coders only: one follow-up round — `hub send` each failing
     slice's coder the failure output (`await: true`), then re-run the gate.
     Isolated coders are disposed after their patch merges and cannot be
     revived — skip this round for them.
  2. Still failing: respawn one fresh coder once (`isolated: false`, the whole
     slice request plus the failure output).
  3. Still failing: `ask` the human — "Stop the run" (recommended) or
     "Retry the coder once more".

### Serial stages — cleaner; architect (full only); hardener; QA

One slice at a time, in slice order, single `task` spawn (`isolated: false`;
one writer on the shared tree). Task text: slice name + project root. After
each spawn completes, verify with the stage's gate:
`bash ./scripts/gates/<role>.sh`. If nonzero: one `hub send` follow-up to that
agent with the failure output (`await: true`) → still failing, respawn the
same role agent once for the slice (failure output included) → still failing,
`ask` the human ("Stop the run" recommended / "Retry once more").

- Architect: after the gate passes, read `specs/<slice>.architecture.md` into
  the final report.
- QA (standard/full, last): before verifying, `scripts/qa/<slice>.sh` must
  exist (the QA agent wrote it). QA's summary includes its handoff
  verification of the earlier gates.

### gate: "missing" / untooled language

If any role yields `gate: "missing"`, or any gate output says
`run /swarm init to choose ...`, **stop the run** and report: name the
missing gate script or tools.yml cell, and direct the user to `/swarm init`.
If a tool binary is missing, report its install command. Never advance
stages past a missing gate.

### Isolation failures and merge conflicts

- If the isolated batch fails with "requires a git repository" or a backend
  error: retry that stage serially (`isolated: false`), run all remaining
  stages serial, and report the fallback.
- If parallel coders' merge produces a conflict (stashConflict / patch-apply
  failure): respawn one coder (`isolated: false`) to reconcile; a second
  failure ⇒ `ask` the human.

## Completion

Compile per-slice evidence: every stage's `gate: pass` plus its gate output,
changed files, and the architect report (full pipeline). Then the final human
gate: `ask` with options "Accept" (recommended), "Request changes" (the user
states a delta; respawn a coder for it and re-run cleaner → hardener → QA on
the delta), "Stop". Never claim the run is done without QA `gate: pass`
(standard/full) or cleaner `gate: pass` (quick).

## Steering

Role agents may message Main via `hub` (blocked, stuck, equivalent mutant).
Answer directly when you can; otherwise escalate to an `ask`.
