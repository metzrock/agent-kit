#!/usr/bin/env bash
# Sandboxed end-to-end driver for the kit's user-facing flows; with --record it
# also renders the VHS demo GIFs of flows that pass.
#
#   tests/e2e/run.sh [--record] [flow ...]
#
# No flow names runs every flow except the opt-in ones (addons, live-claude),
# which use the network or Claude and only run when named.
# Env: E2E_REF (kit tag under test, default v0.1.3), E2E_OLD_REF (default v0.1.2),
#      E2E_SCRATCH (where --record leaves last-frame PNGs).
# Flow functions are called indirectly through run_one.
# shellcheck disable=SC2317
set -euo pipefail
set -E

# Everything about the real setup is captured here, before any HOME change.
REAL_HOME=$HOME
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
E2E_REF=${E2E_REF:-v0.1.3}
E2E_OLD_REF=${E2E_OLD_REF:-v0.1.2}
SCRATCH=${E2E_SCRATCH:-${TMPDIR:-/tmp}/agent-kit-e2e}
RAW_URL=https://raw.githubusercontent.com/metzrock/agent-kit

DEFAULT_FLOWS=(quickstart dry-run install modules doctor-list statusline customize restore update uninstall)
OPT_IN_FLOWS=(addons live-claude)
RECORD_FLOWS=(install modules statusline uninstall addons customize update)
TOOL_NAMES=(gum claude node npx npm python3)
TOOL_SRC=()
for _t in "${TOOL_NAMES[@]}"; do
  _p=$(command -v "$_t" 2>/dev/null || true)
  [[ -z $_p ]] || TOOL_SRC+=("$_p")
done
VHS_SRC=()
for _t in vhs ttyd ffmpeg ffprobe; do
  _p=$(command -v "$_t" 2>/dev/null || true)
  [[ -z $_p ]] || VHS_SRC+=("$_p")
done
unset _t _p

RUN_DIR=$(mktemp -d)
RECORD=0
SB='' KIT='' KIT_BIN=''

die() {
  printf 'FAIL: %s\n' "$*" >&2
  printf '%s\n' "$*" >"$RUN_DIR/reason"
  exit 1
}

# ---------------------------------------------------------------- fingerprint

fingerprint() {
  local h=$REAL_HOME f d
  for f in "$h/.claude/settings.json" "$h/.claude/CLAUDE.md" "$h/.config/herdr/config.toml" "$h/.claude/plugins/installed_plugins.json"; do
    if [[ -e $f ]]; then sha256sum "$f" | sed "s|$h|~|"; else echo "absent $f"; fi
  done
  for d in "$h/.claude/agents" "$h/.claude/rules" "$h/.claude/skills" "$h/.local/bin"; do
    echo "== $d"
    # Names, types, modes and link targets; no file contents.
    find "$d" -maxdepth 1 -type d -printf '%p d %m\n' -o -printf '%p %y %m %s %T@ %l\n' 2>&1 | sort
  done
  echo "== $h/.config/agent-kit"
  find "$h/.config/agent-kit" -name .lock -prune -o -type d -printf '%p d %m\n' -o -printf '%p %y %m %s %T@ %l\n' 2>&1 | sort
  echo "== repo"
  git -C "$REPO_ROOT" rev-parse HEAD
  if (( RECORD )); then
    # Recording writes the GIFs, and this session edits the tapes.
    git -C "$REPO_ROOT" status --porcelain | grep -v ' docs/demo/' || true
  else
    git -C "$REPO_ROOT" status --porcelain
  fi
}

# ---------------------------------------------------------------- sandbox

# A fresh HOME in a fresh temp dir; refuses anything that could be the real home.
sandbox_new() {
  local sb v t
  sb=$(mktemp -d)
  [[ -d $sb && $sb == /* ]] || die "mktemp gave no directory: $sb"
  [[ $sb != "$REAL_HOME" && $sb != "$REAL_HOME"/* ]] || die "sandbox $sb is inside the real home"
  SB=$sb
  mkdir "$SB/home" "$SB/tools"
  for t in ${TOOL_SRC[@]+"${TOOL_SRC[@]}"}; do ln -s "$t" "$SB/tools/$(basename "$t")"; done
  HOME=$SB/home
  [[ $HOME != "$REAL_HOME" && $HOME == "$SB"/home && -z $(ls -A "$HOME") ]] || die "unsafe sandbox HOME: $HOME"
  export HOME
  PATH=$HOME/.local/bin:$SB/tools:/usr/local/bin:/usr/bin:/bin
  export PATH
  unset CLAUDE_CONFIG_DIR
  for v in $(compgen -e | grep '^XDG_' || true); do unset "$v"; done
  echo "$SB" >>"$RUN_DIR/sandboxes"
  # The first sandbox of a flow holds the flow's log.
  if [[ -z ${LOG_SET:-} ]]; then
    LOG_SET=1
    exec >"$SB/log" 2>&1
  fi
  printf '== sandbox %s (HOME=%s)\n' "$SB" "$HOME"
}

kit_clone() {
  local ref=${KIT_CLONE_REF:-$E2E_REF}
  git -c advice.detachedHead=false clone -q --branch "$ref" "$REPO_ROOT" "$SB/kit"
  KIT=$SB/kit
  KIT_BIN=$KIT/bin/agent-kit
}

# customize only offers the Herdr settings when herdr is on PATH; a stub is enough.
stub_herdr() { printf '#!/bin/sh\nexit 0\n' >"$SB/tools/herdr"; chmod +x "$SB/tools/herdr"; }

kit() { "${KIT_BIN:-$KIT/bin/agent-kit}" "$@"; }

assert_doctor_clean() {
  local out rc=0
  out=$(kit doctor 2>&1) || rc=$?
  printf '%s\n' "$out"
  [[ $rc == 0 ]] || die "doctor exited $rc"
  if grep -Eq '^(MISSING|BROKEN)' <<<"$out"; then die 'doctor reported MISSING or BROKEN lines'; fi
}

installed_set() { kit list --json | jq -r '[.[] | select(.installed) | .name] | sort | join(" ")'; }

assert_modules() {
  local want got
  want=$(tr ' ' '\n' <<<"$1" | sort | paste -sd' ')
  got=$(installed_set)
  [[ $got == "$want" ]] || die "installed modules are '$got', expected '$want'"
}

assert_eq() { [[ $1 == "$2" ]] || die "$3: got '$1', expected '$2'"; }

settings_hash() { sha256sum "$HOME/.claude/settings.json" | cut -d' ' -f1; }

# After an uninstall nothing may remain except timestamped backups.
assert_only_backups() {
  local remaining
  remaining=$(find "$HOME" \( -type f -o -type l \) ! -path '*/.local/state/agent-kit/backups/*')
  [[ -z $remaining ]] || die "files remain after uninstall: $remaining"
}

# ---------------------------------------------------------------- flows

flow_quickstart() {
  sandbox_new
  KIT_BIN=$HOME/.local/bin/agent-kit
  export GIT_TERMINAL_PROMPT=0
  timeout 600 curl -fsSL "$RAW_URL/$E2E_REF/install.sh" | timeout 600 bash -s -- --yes
  assert_eq "$(git -C "$HOME/.local/share/agent-kit" describe --tags --exact-match)" "$E2E_REF" 'installed checkout tag'
  assert_modules 'base lean usage crew look'
  assert_doctor_clean
}

flow_dry_run() {
  sandbox_new; kit_clone
  local out
  out=$(kit install --dry-run); echo "$out"
  grep -q 'Would install: base lean usage crew look' <<<"$out" || die 'dry-run output does not name the five core modules'
  out=$(kit install --modules crew --dry-run); echo "$out"
  grep -q 'Would install: base lean crew' <<<"$out" || die 'crew dry-run does not pull in lean'
  [[ -z $(ls -A "$HOME") ]] || die "dry-run left files in HOME: $(ls -A "$HOME")"
}

flow_install() {
  sandbox_new; kit_clone
  local before
  kit install --yes
  before=$(settings_hash)
  kit install --yes
  assert_eq "$(settings_hash)" "$before" 'settings.json hash after second install'
  assert_modules 'base lean usage crew look'
  assert_doctor_clean
}

flow_modules() {
  sandbox_new; kit_clone
  kit install --modules usage,look --model sonnet --yes
  assert_modules 'base usage look'
  assert_eq "$(jq -r .model "$HOME/.claude/settings.json")" sonnet 'settings.json model'
  assert_doctor_clean
}

flow_doctor_list() {
  sandbox_new; kit_clone
  local json
  kit install --yes
  json=$(kit list --json)
  assert_eq "$(jq length <<<"$json")" 9 'list --json entries'
  assert_eq "$(jq -r '[.[] | select(.installed) | .name] | join(" ")' <<<"$json")" 'base lean usage crew look' 'installed flags'
  assert_eq "$(jq -r '[.[] | select(.installed | not) | .name] | join(" ")' <<<"$json")" 'plannotator design writing devtools' 'not-installed flags'
  kit list >/dev/null
  kit doctor >/dev/null
}

write_sample_status() {
  printf '%s' '{"model":{"display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}' >"$HOME/sample-status.json"
}

flow_statusline() {
  sandbox_new; kit_clone
  local out
  kit install --modules usage --yes
  write_sample_status
  out=$(claude-statusline <"$HOME/sample-status.json"); echo "$out"
  grep -q '5h 23%' <<<"$out" || die 'statusline lacks "5h 23%"'
  grep -q 'wk 41%' <<<"$out" || die 'statusline lacks "wk 41%"'
  out=$(prompt-clock </dev/null | jq -r .hookSpecificOutput.additionalContext); echo "$out"
  [[ -n $out && $out != null ]] || die 'prompt-clock additionalContext is empty'
}

flow_customize() {
  sandbox_new; kit_clone
  kit install --modules base --yes
  # Without herdr or crew: settings only, no look module, no Herdr config.
  kit customize </dev/null
  echo "settings.json after customize:"; jq -S . "$HOME/.claude/settings.json"
  assert_eq "$(jq -r .theme "$HOME/.claude/settings.json")" dark 'settings.json theme'
  assert_modules base
  [[ ! -e $HOME/.config/herdr/config.toml ]] || die 'customize wrote a Herdr config without herdr or crew'
  # With herdr on PATH it also writes the Herdr config.
  stub_herdr
  kit customize </dev/null
  [[ -f $HOME/.config/herdr/config.toml ]] || die 'customize left no ~/.config/herdr/config.toml with herdr on PATH'
  assert_doctor_clean
}

flow_restore() {
  sandbox_new; kit_clone
  local link out rc=0
  kit install --yes
  link=$(jq -r '[.files[] | select(.kind == "link")][0].path' "$HOME/.config/agent-kit/state.json")
  [[ -L $link ]] || die "expected a kit link at $link"
  rm "$link"
  out=$(kit doctor 2>&1) || rc=$?
  echo "$out"
  [[ $rc != 0 ]] || die 'doctor exited 0 with a deleted link'
  grep -q '^BROKEN' <<<"$out" || die 'doctor did not print BROKEN'
  # No origin: update refreshes the local checkout instead of fetching.
  git -C "$KIT" remote remove origin
  kit update </dev/null
  [[ -L $link ]] || die "update did not restore $link"
  assert_doctor_clean
}

flow_update() {
  sandbox_new
  KIT_BIN=$HOME/.local/bin/agent-kit
  export GIT_TERMINAL_PROMPT=0
  local before
  timeout 600 curl -fsSL "$RAW_URL/$E2E_REF/install.sh" | AGENT_KIT_REF=$E2E_OLD_REF timeout 600 bash -s -- --yes
  assert_eq "$(git -C "$HOME/.local/share/agent-kit" describe --tags --exact-match)" "$E2E_OLD_REF" 'checkout tag before update'
  # The user edited their copy; a non-interactive update must keep it.
  echo '- my own note' >>"$HOME/.claude/CLAUDE.md"
  before=$(sha256sum "$HOME/.claude/CLAUDE.md")
  timeout 600 "$KIT_BIN" update </dev/null
  assert_eq "$(git -C "$HOME/.local/share/agent-kit" describe --tags --exact-match)" "$E2E_REF" 'checkout tag after update'
  assert_eq "$(sha256sum "$HOME/.claude/CLAUDE.md")" "$before" 'CLAUDE.md hash after update'
  assert_doctor_clean
}

flow_uninstall() {
  sandbox_new; kit_clone
  kit install --yes
  kit uninstall usage
  assert_modules 'base lean crew look'
  if kit uninstall base; then die 'uninstall base succeeded while other modules are installed'; fi
  if kit uninstall lean; then die 'uninstall lean succeeded while crew is installed'; fi
  assert_modules 'base lean crew look'
  kit uninstall
  assert_only_backups
}

flow_addons() {
  sandbox_new; kit_clone
  local m
  export GIT_TERMINAL_PROMPT=0
  timeout 1800 "$KIT_BIN" install --modules plannotator,design,writing,devtools --yes
  for m in plannotator design writing devtools; do
    jq -e --arg m "$m" '.modules | index($m) != null' "$HOME/.config/agent-kit/state.json" >/dev/null || die "add-on $m is not in state .modules"
  done
  jq -e '.upstream | length > 0' "$HOME/.config/agent-kit/state.json" >/dev/null || die 'state .upstream is empty'
  assert_doctor_clean
}

flow_live_claude() {
  sandbox_new; kit_clone
  local cred=$REAL_HOME/.claude/.credentials.json out
  # Remove the symlink first so a recursive delete can never reach the target.
  trap 'rm -f "$HOME/.claude/.credentials.json" "$SB/.claude.json" 2>/dev/null || true' EXIT
  [[ -f $cred ]] || die 'no ~/.claude/.credentials.json to link'
  mkdir -p "$HOME/.claude"
  ln -s "$cred" "$HOME/.claude/.credentials.json"
  printf '%s\n' '{"hasCompletedOnboarding":true,"theme":"dark"}' >"$HOME/.claude.json"
  kit install --modules base --yes
  [[ -f $HOME/.claude/skills/kit-interview/SKILL.md ]] || die 'kit-interview skill is not linked'
  out=$(printf 'Reply with only the word ready' | timeout 180 claude -p --model sonnet --max-turns 1) || die "claude -p failed: $out"
  echo "$out"
  grep -qi ready <<<"$out" || die 'claude did not answer "ready"'
  out=$(cd "$KIT" && printf 'Read the file %s/GIVE_THIS_TO_YOUR_AGENT.md and reply with only the numbered list of steps it would take, without running anything' "$KIT" |
    timeout 300 claude -p --model sonnet --max-turns 3 --allowedTools Read) || die "claude -p (steps) failed: $out"
  echo "$out"
  [[ -n $out ]] || die 'claude gave no output for the steps prompt'
  grep -qi 'agent-kit' <<<"$out" || die 'steps do not mention agent-kit'
}

# ---------------------------------------------------------------- recording

# Pre-state a tape needs beyond a clone and an empty HOME.
demo_prepare_update() {
  export GIT_TERMINAL_PROMPT=0
  timeout 600 curl -fsSL "$RAW_URL/$E2E_REF/install.sh" | AGENT_KIT_REF=$E2E_OLD_REF timeout 600 bash -s -- --yes
  DEMO_KIT=$HOME/.local/share/agent-kit
  KIT_BIN=$DEMO_KIT/bin/agent-kit
}

# Post-conditions on the HOME the tape ran in (HOME is DEMO_HOME here).
demo_check_install() { assert_modules 'base lean usage crew look'; assert_doctor_clean; }
demo_check_modules() { assert_modules base; assert_doctor_clean; }
demo_check_statusline() { assert_modules 'base usage'; assert_doctor_clean; [[ -f $HOME/sample-status.json ]] || die 'tape wrote no ~/sample-status.json'; }
demo_check_uninstall() { assert_only_backups; }
demo_check_addons() {
  jq -e '.modules | index("writing") != null' "$HOME/.config/agent-kit/state.json" >/dev/null || die 'writing add-on is not installed'
  assert_doctor_clean
}
demo_check_customize() {
  [[ -f $HOME/.config/herdr/config.toml ]] || die 'no herdr config after customize'
  assert_eq "$(jq -r .theme "$HOME/.claude/settings.json")" light 'settings.json theme picked in the tape'
  grep -q 'name = "catppuccin"' "$HOME/.config/herdr/config.toml" || die 'Herdr theme from the tape not applied'
  assert_modules 'base look'
  assert_doctor_clean
}
demo_check_update() {
  assert_eq "$(git -C "$DEMO_KIT" describe --tags --exact-match)" "$E2E_REF" 'checkout tag after the tape'
  assert_doctor_clean
}

# A 64-colour palette built from the changing pixels; keep it only if it is smaller.
shrink_gif() {
  local ffmpeg=$1 gif=$2 dir
  dir=$(mktemp -d)
  "$ffmpeg" -y -loglevel error -i "$gif" -vf 'palettegen=max_colors=64:stats_mode=diff' "$dir/palette.png"
  "$ffmpeg" -y -loglevel error -i "$gif" -i "$dir/palette.png" -lavfi 'paletteuse=dither=none:diff_mode=rectangle' "$dir/small.gif"
  if (( $(stat -c %s "$dir/small.gif") < $(stat -c %s "$gif") )); then mv "$dir/small.gif" "$gif"; fi
  rm -rf "$dir"
}

record_flow() {
  local name=$1 tape=docs/demo/$1.tape gif=docs/demo/$1.gif vhsbin src
  [[ -f $REPO_ROOT/$tape ]] || die "no tape $tape"
  sandbox_new; kit_clone
  DEMO_HOME=$HOME
  DEMO_KIT=$KIT
  DEMO_PATH=$PATH
  if [[ $name == update ]]; then demo_prepare_update; fi
  if [[ $name == customize ]]; then stub_herdr; fi
  vhsbin=$SB/vhsbin
  mkdir "$vhsbin"
  for src in ${VHS_SRC[@]+"${VHS_SRC[@]}"}; do ln -s "$src" "$vhsbin/$(basename "$src")"; done
  rm -f "$REPO_ROOT/$gif"
  # vhs itself needs the real HOME (browser cache); the tape exports the demo HOME.
  (cd "$REPO_ROOT" && env HOME="$REAL_HOME" PATH="$vhsbin:/usr/local/bin:/usr/bin:/bin" \
    LD_LIBRARY_PATH="$REAL_HOME/.local/lib/vhs-nss" \
    DEMO_HOME="$DEMO_HOME" DEMO_KIT="$DEMO_KIT" DEMO_PATH="$DEMO_PATH" \
    timeout 900 vhs "$tape")
  [[ -f $REPO_ROOT/$gif ]] || die "vhs produced no $gif"
  shrink_gif "$vhsbin/ffmpeg" "$REPO_ROOT/$gif"
  "demo_check_${name//-/_}"
  mkdir -p "$SCRATCH"
  "$vhsbin/ffmpeg" -y -loglevel error -sseof -0.1 -i "$REPO_ROOT/$gif" -frames:v 1 "$SCRATCH/$name-last.png"
  [[ -f $SCRATCH/$name-last.png ]] || die 'no last frame extracted'
  echo "$SCRATCH/$name-last.png" >"$RUN_DIR/frame"
}

# ---------------------------------------------------------------- runner

contains() { local x=$1; shift; local y; for y in "$@"; do [[ $x == "$y" ]] && return 0; done; return 1; }

# Run a function (with args) in a subshell with its own sandbox; print PASS/FAIL.
run_one() {
  local label=$1 rc sb
  shift
  : >"$RUN_DIR/sandboxes"; rm -f "$RUN_DIR/reason" "$RUN_DIR/frame"
  set +e
  (
    set -eE
    trap 'rc=$?; [[ -s $RUN_DIR/reason ]] || echo "command failed (exit $rc) at line $LINENO: $BASH_COMMAND" >"$RUN_DIR/reason"' ERR
    "$@"
  )
  rc=$?
  set -e
  if (( rc == 0 )); then
    printf 'PASS %s\n' "$label"
    [[ ! -f $RUN_DIR/frame ]] || printf '  last frame: %s\n' "$(cat "$RUN_DIR/frame")"
    while IFS= read -r sb; do
      [[ $sb == /* && $sb != "$REAL_HOME" && $sb != / ]] && rm -rf "$sb"
    done <"$RUN_DIR/sandboxes"
    return 0
  fi
  local reason; reason=$(cat "$RUN_DIR/reason" 2>/dev/null || echo "exit $rc")
  printf 'FAIL %s: %s\n' "$label" "$reason"
  sb=$(head -1 "$RUN_DIR/sandboxes" 2>/dev/null || true)
  if [[ -n $sb && -f $sb/log ]]; then
    printf '  sandbox kept: %s\n  --- last 30 log lines ---\n' "$sb"
    tail -n 30 "$sb/log" | sed 's/^/  | /'
  fi
  if [[ $label == live-claude && -n $sb ]]; then
    # Always remove this one; it may have held a credentials symlink.
    rm -f "$sb/home/.claude/.credentials.json"
    rm -rf "$sb"
    echo '  (live-claude sandbox removed)'
  fi
  return 1
}

cleanup() {
  HOME=$REAL_HOME; export HOME
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT
trap 'echo "interrupted" >&2; exit 130' INT TERM

main() {
  local flows=() f failed=0 before after
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --record) RECORD=1 ;;
      -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
      -*) echo "unknown option: $1" >&2; exit 2 ;;
      *) flows+=("$1") ;;
    esac
    shift
  done
  if (( RECORD )) && [[ ${#flows[@]} -eq 0 ]]; then echo '--record needs flow names' >&2; exit 2; fi
  [[ ${#flows[@]} -gt 0 ]] || flows=("${DEFAULT_FLOWS[@]}")
  for f in "${flows[@]}"; do
    if (( RECORD )); then
      contains "$f" "${RECORD_FLOWS[@]}" || { echo "no tape for flow: $f" >&2; exit 2; }
    else
      contains "$f" "${DEFAULT_FLOWS[@]}" "${OPT_IN_FLOWS[@]}" || { echo "unknown flow: $f" >&2; exit 2; }
    fi
  done
  [[ $REAL_HOME == /* && -d $REAL_HOME ]] || { echo 'HOME is not a real directory' >&2; exit 1; }
  git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$E2E_REF" >/dev/null || { echo "tag $E2E_REF not found in $REPO_ROOT" >&2; exit 1; }

  before=$(fingerprint)
  for f in "${flows[@]}"; do
    if (( RECORD )); then
      run_one "$f" "flow_${f//-/_}" || { failed=1; continue; }
      run_one "record:$f" record_flow "$f" || failed=1
    else
      run_one "$f" "flow_${f//-/_}" || failed=1
    fi
  done
  after=$(fingerprint)
  if [[ $before == "$after" ]]; then
    echo 'PASS fingerprint (real setup unchanged)'
  else
    echo 'FAIL fingerprint: the real setup changed during the run'
    diff <(echo "$before") <(echo "$after") | head -40 || true
    failed=1
  fi
  exit "$failed"
}

main "$@"
