#!/usr/bin/env bash
# Unit tests for the swarm gate machinery. Run: bash test.sh
set -uo pipefail
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/swarm-gates-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
TPL="${SWARM_TPL:-$HOME/.omp/agent/skills/swarm/templates}"
pass=0 fail=0

ok()   { pass=$((pass+1)); echo "PASS: $1"; }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { # check <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want [$2] got [$3])"; fi
}
check_nz() { # check_nz <desc> <exitcode>
  if [[ "$2" -ne 0 ]]; then ok "$1"; else bad "$1 (want nonzero, got 0)"; fi
}
check_z() { # check_z <desc> <exitcode>
  if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1 (want 0, got $2)"; fi
}

install_gates() { # install_gates <dir>
  mkdir -p "$1/scripts/gates" "$1/tools"
  cp "$TPL/gates/"*.sh "$TPL/gates/tools.defaults.yml" "$1/scripts/gates/"
  cp "$TPL/tools/crap.py" "$1/tools/"
  chmod +x "$1"/scripts/gates/*.sh "$1/tools/crap.py"
}

echo "=== detect.sh ==="
D="$ROOT/r-detect"; rm -rf "$D"; mkdir -p "$D"
install_gates "$D"
out="$(bash "$D/scripts/gates/detect.sh")"
check "empty repo detects nothing" "" "$out"

touch "$D/pyproject.toml"
check "pyproject.toml detects py" "py" "$(bash "$D/scripts/gates/detect.sh")"
rm "$D/pyproject.toml"; touch "$D/setup.py"
check "setup.py detects py" "py" "$(bash "$D/scripts/gates/detect.sh")"
rm "$D/setup.py"; touch "$D/requirements-dev.txt"
check "requirements*.txt detects py" "py" "$(bash "$D/scripts/gates/detect.sh")"
rm "$D/requirements-dev.txt"
touch "$D/go.mod" "$D/package.json" "$D/setup.cfg"
check "go+ts+py detects all three" "go
py
ts" "$(bash "$D/scripts/gates/detect.sh")"

echo "=== resolve + run (py only, tools.yml override) ==="
D="$ROOT/r-py"; rm -rf "$D"; mkdir -p "$D"
install_gates "$D"
touch "$D/pyproject.toml"
cat > "$D/scripts/gates/tools.yml" <<'YML'
py:
  coder: "echo coder-ran && true"
YML
out="$(bash "$D/scripts/gates/coder.sh" 2>&1)"; rc=$?
check_z "py coder gate passes" "$rc"
[[ "$out" == *"coder-ran"* ]] && ok "coder command executed" || bad "coder command executed: $out"
[[ "$out" != *"/swarm init"* ]] && ok "no init message when cell exists" || bad "no init message when cell exists: $out"

echo "=== missing cell -> init message, nonzero ==="
rm "$D/scripts/gates/tools.yml"
mv "$D/scripts/gates/tools.defaults.yml" "$D/scripts/gates/tools.defaults.yml.bak"
out="$(bash "$D/scripts/gates/coder.sh" 2>&1)"; rc=$?
check_nz "missing tools.yml + defaults -> nonzero" "$rc"
[[ "$out" == *"run /swarm init"* ]] && ok "missing cell prints /swarm init hint" || bad "missing cell prints /swarm init hint: $out"
mv "$D/scripts/gates/tools.defaults.yml.bak" "$D/scripts/gates/tools.defaults.yml"

echo "=== defaults fallback when tools.yml lacks a cell ==="
out="$(bash "$D/scripts/gates/coder.sh" 2>&1)"; rc=$?
check_nz "no tools.yml: defaults run (nonzero: pytest missing)" "$rc"
[[ "$out" == *"python3 -m pytest"* ]] && ok "defaults fallback ran the default command" || bad "defaults fallback ran the default command: $out"

echo "=== defaults fallback ==="
cat > "$D/scripts/gates/tools.yml" <<'YML'
py:
  cleaner: "echo cleaner-ran && true"
YML
out="$(bash "$D/scripts/gates/cleaner.sh" 2>&1)"; rc=$?
check_z "cleaner uses tools.yml cell" "$rc"
[[ "$out" == *"cleaner-ran"* ]] && ok "tools.yml cell wins" || bad "tools.yml cell wins: $out"

echo "=== multi-language dispatch ==="
D="$ROOT/r-multi"; rm -rf "$D"; mkdir -p "$D"
install_gates "$D"
touch "$D/go.mod" "$D/package.json"
cat > "$D/scripts/gates/tools.yml" <<'YML'
go:
  coder: "echo go-coder-ran && true"
ts:
  coder: "echo ts-coder-ran && true"
YML
out="$(bash "$D/scripts/gates/coder.sh" 2>&1)"; rc=$?
check_z "go+ts coder gate passes" "$rc"
[[ "$out" == *"go-coder-ran"* && "$out" == *"ts-coder-ran"* ]] && ok "both lang commands ran" || bad "both lang commands ran: $out"

cat > "$D/scripts/gates/tools.yml" <<'YML'
go:
  coder: "echo go-ok && true"
ts:
  coder: "echo ts-fails && false"
YML
bash "$D/scripts/gates/coder.sh" >/dev/null 2>&1; rc=$?
check_nz "one lang failing -> gate nonzero" "$rc"

echo "=== defaults content integrity ==="
D="$ROOT/r-def"; rm -rf "$D"; mkdir -p "$D"
install_gates "$D"
touch "$D/pyproject.toml"
cmd="$(bash "$D/scripts/gates/detect.sh" >/dev/null 2>&1; true)"
res="$(source "$D/scripts/gates/lib.sh"; swarm_resolve_cmd py hardener)"
check "py hardener default resolves" 'mutmut run && out="$(mutmut results --all false)" && [ -z "$out" ]' "$res"
res="$(source "$D/scripts/gates/lib.sh"; swarm_resolve_cmd py cleaner)"
[[ "$res" == *"crap.py --max 6"* && "$res" == *"--cov-fail-under=90"* ]] && ok "py cleaner default intact" || bad "py cleaner default intact: $res"
res="$(source "$D/scripts/gates/lib.sh"; swarm_resolve_cmd ts architect)"
check "ts architect default intact" $'! grep -rnE "(require|from) [\'\\"](tests|scripts)" src' "$res"

echo "=== qa.sh ==="
D="$ROOT/r-qa"; rm -rf "$D"; mkdir -p "$D"
install_gates "$D"
bash "$D/scripts/gates/qa.sh" >/dev/null 2>&1; rc=$?
check_nz "qa with no checks fails" "$rc"
mkdir -p "$D/scripts/qa"
cat > "$D/scripts/qa/s1.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# AC-1
[ "$(echo hi)" = "hi" ]
SH
bash "$D/scripts/gates/qa.sh" >/dev/null 2>&1; rc=$?
check_z "qa with passing check passes" "$rc"
cat > "$D/scripts/qa/s1.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# AC-1
[ "$(echo hi)" = "wrong" ]
SH
bash "$D/scripts/gates/qa.sh" >/dev/null 2>&1; rc=$?
check_nz "qa with failing check fails" "$rc"

echo "=== crap.py ==="
D="$ROOT/r-crap"; rm -rf "$D"; mkdir -p "$D/app"
cat > "$D/app/m.py" <<'PY'
def simple(a, b):
    return a + b

def borderline(x):
    # 1 + 5 ifs = 6 -> passes at max 6
    r = 0
    if x == 1: r = 1
    if x == 2: r = 2
    if x == 3: r = 3
    if x == 4: r = 4
    if x == 5: r = 5
    return r

def too_big(x):
    # 1 + 6 ifs = 7 -> fails at max 6
    r = 0
    if x == 1: r = 1
    if x == 2: r = 2
    if x == 3: r = 3
    if x == 4: r = 4
    if x == 5: r = 5
    if x == 6: r = 6
    return r

def outer(a, b):
    def inner(c):
        if c:
            return 1
        return 0
    return inner(a) + b

def extras(xs, flag):
    # ternary +1, and +1, comprehension +1, or +1
    total = sum(v for v in xs)
    if total > 0 and flag:
        return "yes" if total > 1 else "no"
    return "maybe" or "x"
PY
"$ROOT/r-crap/app/../tools" 2>/dev/null || true
PY="$(command -v python3)"
"$PY" "$TPL/tools/crap.py" --max 6 "$D/app" >"$D/out.txt" 2>"$D/err.txt"; rc=$?
check_nz "complexity 7 function fails gate" "$rc"
[[ "$(cat "$D/out.txt")" == *"borderline: 6"* ]] && ok "borderline scored 6" || bad "borderline scored 6: $(cat "$D/out.txt")"
[[ "$(cat "$D/out.txt")" == *"too_big: 7"* ]] && ok "too_big scored 7" || bad "too_big scored 7: $(cat "$D/out.txt")"
[[ "$(cat "$D/out.txt")" == *"outer: 1"* ]] && ok "nested def does not inflate outer" || bad "nested def does not inflate outer: $(cat "$D/out.txt")"
[[ "$(cat "$D/out.txt")" == *"extras: 6"* ]] && ok "ternary/and/or/if/comprehension counted (extras: 6)" || bad "extras count: $(cat "$D/out.txt")"
[[ "$(cat "$D/out.txt")" == *"inner: 2"* ]] && ok "nested fn scored separately" || bad "nested fn scored separately: $(cat "$D/out.txt")"
rm "$D/app/m.py"; printf 'def f(a, b):\n    return a + b\n' > "$D/app/m.py"
"$PY" "$TPL/tools/crap.py" --max 6 "$D/app" >/dev/null 2>&1; rc=$?
check_z "all-simple functions pass gate" "$rc"

echo
echo "=== result: $pass pass, $fail fail ==="
[[ "$fail" -eq 0 ]]
