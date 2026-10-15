#!/usr/bin/env bats
load helper
@test "external skill directory stays untouched throughout install update uninstall" {
  other=$BATS_TEST_TMPDIR/other
  mkdir -p "$other/dir" "$HOME/.claude/skills"
  echo untouched >"$other/dir/keep"
  ln -s "$other/dir" "$HOME/.claude/skills/herdr-crew"
  run "$KIT_ROOT/bin/agent-kit" install --modules crew --yes
  [[ $status == 0 && $output == *"Skipping user-owned symlink directory"* ]]
  "$KIT_ROOT/bin/agent-kit" update --local
  run "$KIT_ROOT/bin/agent-kit" doctor
  [[ $output == *USER-OWNED* ]]
  "$KIT_ROOT/bin/agent-kit" uninstall
  [[ $(ls -A "$other/dir") == keep && $(cat "$other/dir/keep") == untouched ]]
}
@test "normalized hooks and preexisting statusLine stay user owned" {
  mkdir -p "$HOME/.claude"
  cat >"$HOME/.claude/settings.json" <<'JSON'
{"statusLine":{"command":"claude-statusline","custom":true},"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"\"$HOME/.local/bin/prompt-clock\""}]}],"PostToolUse":[{"hooks":[{"type":"command","command":"~/.local/bin/usage-watch"}]}]}}
JSON
  cp "$HOME/.claude/settings.json" "$HOME/original"
  "$KIT_ROOT/bin/agent-kit" install --modules usage --yes
  "$KIT_ROOT/bin/agent-kit" update --local
  jq -e '(.hooks.UserPromptSubmit|length)==1 and (.hooks.PostToolUse|length)==1 and .statusLine.custom' "$HOME/.claude/settings.json"
  "$KIT_ROOT/bin/agent-kit" uninstall
  cmp "$HOME/original" "$HOME/.claude/settings.json"
}
@test "bare script names match but unrelated executable paths do not" {
  common
  echo '{"hooks":{"Stop":[{"hooks":[{"command":"usage-watch"}]},{"hooks":[{"command":"/other/prompt-clock"}]}]}}' >"$HOME/settings.json"
  patch=$(jq -cn --arg h "$HOME" '{hooks:{Stop:[{hooks:[{command:($h+"/.local/bin/usage-watch")}]},{hooks:[{command:($h+"/.local/bin/prompt-clock")}]},{hooks:[{command:"echo user"}]}]}}')
  settings_merge "$HOME/settings.json" "$patch"
  jq -e '.hooks.Stop|length==4' "$HOME/settings.json"
  uninstall_module base
  jq -e '.hooks.Stop|length==2' "$HOME/settings.json"
}
@test "hooks in a multi-command group deduplicate individually and scalar statusLine survives" {
  common
  echo '{"statusLine":"custom","hooks":{"Stop":[{"hooks":[{"command":"prompt-clock"},{"command":"echo user"}]}]}}' >"$HOME/settings.json"
  patch='{"statusLine":{"type":"command","command":"claude-statusline"},"hooks":{"Stop":[{"hooks":[{"command":"~/.local/bin/prompt-clock"},{"command":"usage-watch"}]}]}}'
  settings_merge "$HOME/settings.json" "$patch"
  jq -e '.statusLine=="custom" and .hooks.Stop[1].hooks==[{command:"usage-watch"}]' "$HOME/settings.json"
  uninstall_module base
  jq -e '.hooks.Stop|length==1' "$HOME/settings.json"
}
@test "a directory replaced by an external symlink after install is safe on uninstall" {
  common
  mkdir -p "$HOME/owned" "$BATS_TEST_TMPDIR/other"
  link_kit_file "$KIT_ROOT/LICENSE" "$HOME/owned/file"
  mv "$HOME/owned/file" "$BATS_TEST_TMPDIR/other/file"
  rmdir "$HOME/owned"
  ln -s "$BATS_TEST_TMPDIR/other" "$HOME/owned"
  uninstall_module base
  [[ -L $BATS_TEST_TMPDIR/other/file ]]
}
clock_fixture() {
  export TZ=UTC AGENT_KIT_USAGE_CACHE="$HOME/cache" CODEX_HOME="$HOME/codex"
  mkdir -p "$HOME/mock" "$AGENT_KIT_USAGE_CACHE" "$CODEX_HOME/sessions"
  export REAL_DATE
  REAL_DATE=$(command -v date)
  cat >"$HOME/mock/date" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  +%s) echo 2000000000 ;;
  +*) exec "$REAL_DATE" -d @2000000000 "$@" ;;
  *) exec "$REAL_DATE" "$@" ;;
esac
MOCK
  chmod +x "$HOME/mock/date"
  export PATH="$HOME/mock:$PATH"
  echo '{"session_id":"abcdefgh-more","prompt_cache":{"expires_at":1999999999,"recache_tokens_if_cold":60000},"rate_limits":{"five_hour":{"used_percentage":83,"resets_at":2000007200},"seven_day":{"used_percentage":21,"resets_at":2000086400}}}' >"$AGENT_KIT_USAGE_CACHE/claude-statusline.json"
  touch -d @2000000000 "$AGENT_KIT_USAGE_CACHE/claude-statusline.json"
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":99,"resets_at":1999999999},"secondary":{"used_percent":35,"resets_at":2000086400}}}' >"$CODEX_HOME/sessions/rollout-fixture.jsonl"
  touch -d @1999998800 "$CODEX_HOME/sessions/rollout-fixture.jsonl"
}
@test "prompt clock exact format and seven column log include reset stale cloud and notes" {
  clock_fixture
  mkdir -p "$HOME/.config/agent-kit" "$HOME/.local/share/cloud-runs"
  echo CLOUD_CREDIT_UNTIL=2033-05-20T03:33:20Z >"$HOME/.config/agent-kit/config"
  printf 'time\t72.90\n' >"$HOME/.local/share/cloud-runs/balance.tsv"
  output=$(echo '{"session_id":"abcdefgh-more"}' | "$KIT_ROOT/modules/usage/files/prompt-clock")
  expected='Current local time: Wednesday 2033-05-18 03:33 UTC · Claude 5h 83% (resets 05:33) · week 21% (resets Thu) · Codex 5h 0% (window reset) · week 35% (resets Thu) [as of 03:13] · Cloud $72 (2d)
Usage note: Claude 5h is low with over an hour to reset: prefer Sonnet/Codex or medium effort
Usage note: prompt cache expired: this turn re-reads ~60k tokens; if the earlier work is finished, suggest /clear or a handoff'
  [[ $(jq -r .hookSpecificOutput.additionalContext <<<"$output") == "$expected" ]]
  log=$HOME/.local/share/usage-log/usage.tsv
  [[ $(head -1 "$log") == $'time\tsession\tclaude_5h\tclaude_week\tcodex_5h\tcodex_week\tcodex_as_of' ]]
  [[ $(tail -1 "$log") == $'2033-05-18T03:33:20+00:00\tabcdefgh\t83\t21\t0\t35\t2033-05-18T03:13:20+00:00' ]]
}
@test "header mismatch rotates once and unknown session is empty" {
  clock_fixture
  mkdir -p "$HOME/.local/share/usage-log"
  printf 'old\theader\noriginal\trow\n' >"$HOME/.local/share/usage-log/usage.tsv"
  run bash -c 'echo "{}" | "$KIT_ROOT/modules/usage/files/prompt-clock"'
  [[ $status == 0 && $output == *"Rotated usage log"* ]]
  [[ $(cat "$HOME/.local/share/usage-log/usage.20330518T033320.tsv") == $'old\theader\noriginal\trow' ]]
  run bash -c 'echo "{}" | "$KIT_ROOT/modules/usage/files/prompt-clock"'
  [[ $status == 0 && $output != *Rotated* ]]
  awk -F '\t' 'NR>1 {if(NF!=7 || $2!="") exit 1}' "$HOME/.local/share/usage-log/usage.tsv"
}
@test "Codex uses first snapshot from at most five newest rollouts in CODEX_HOME" {
  clock_fixture
  for i in 1 2 3 4; do echo '{}' >"$CODEX_HOME/sessions/rollout-$i.jsonl"; touch -d "@$((2000000000+i))" "$CODEX_HOME/sessions/rollout-$i.jsonl"; done
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  usage_snapshot | jq -e '.codex.primary.used_percent==99'
  echo '{}' >"$CODEX_HOME/sessions/rollout-5.jsonl"
  touch -d @2000000005 "$CODEX_HOME/sessions/rollout-5.jsonl"
  jq '.checked_at=0' "$usage_cache/codex-snapshot.json" >"$HOME/newcache"
  mv "$HOME/newcache" "$usage_cache/codex-snapshot.json"
  usage_snapshot | jq -e '.codex==null'
}
crew_double() {
  mkdir -p "$HOME/mock" "$HOME/state"
  cat >"$HOME/mock/herdr" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/commands"
case "$1 $2" in
  'agent get')
    if [[ $3 == reviewer && -f $HOME/reviewer-live ]]; then
      echo '{"result":{"agent":{"pane_id":"split","agent":"codex"}}}'
    else exit 1; fi ;;
  'agent start') [[ $3 != reviewer ]] || touch "$HOME/reviewer-live"; echo '{}' ;;
  'agent prompt') echo reviewed >"$HOME/state/review-1.md"; echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  'agent send-keys') rm -f "$HOME/reviewer-live"; echo '{}' ;;
  'pane layout') echo '{"result":{"layout":{"panes":[{"pane_id":"root","rect":{"width":160}}]}}}' ;;
  'pane split') echo '{"result":{"pane":{"pane_id":"split"}}}' ;;
  'pane read') if [[ ${TRUST_SCREEN:-0} == 1 ]]; then echo 'Trust this folder'; else echo '{}'; fi ;;
  *) echo '{}' ;;
esac
MOCK
  chmod +x "$HOME/mock/herdr"
  export PATH="$HOME/mock:$PATH" HERDR_ENV=1 HERDR_PANE_ID=root CREW_STATE_DIR="$HOME/state" CODEX_HOME="$HOME/codex"
}
@test "Codex profile extra arguments and Sonnet note honor config and env" {
  crew_double
  mkdir -p "$HOME/.config/agent-kit"
  printf 'CREW_IMPLEMENTER=codex\nCREW_IMPL_PROFILE=custom\nCREW_CODEX_ARGS=--approve-for-me --example\nCREW_SONNET_NOTE=Extra generic rule\n' >"$HOME/.config/agent-kit/config"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" up
  [[ $status == 0 ]]
  grep -q -- '-- -p custom --approve-for-me --example -c' "$HOME/commands"
  grep -q 'Extra generic rule' "$HOME/commands"
  [[ ! -e $CODEX_HOME/config.toml ]]
  export CREW_IMPL_PROFILE=override
  "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
  grep -q -- '-- -p override' "$HOME/commands"
}
@test "auto trust is gated idempotent and preserves existing policy" {
  crew_double
  export CREW_IMPLEMENTER=codex TRUST_SCREEN=1
  run "$KIT_ROOT/modules/crew/files/herdr-crew" up
  [[ $status == 1 && $output == *'asking to trust'* && ! -e $CODEX_HOME/config.toml ]]
  export CREW_CODEX_AUTO_TRUST=1 TRUST_SCREEN=0
  "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
  "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
  [[ $(grep -c 'trust_level = "trusted"' "$CODEX_HOME/config.toml") == 1 ]]
  sed -i 's/"trusted"/"untrusted"/' "$CODEX_HOME/config.toml"
  "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
  grep -q 'trust_level = "untrusted"' "$CODEX_HOME/config.toml"
}
@test "second implementer and Codex reviewer both receive profile and extra arguments" {
  crew_double
  export CREW_IMPLEMENTER=codex CREW_IMPL_PROFILE=custom CREW_CODEX_ARGS=--approve-for-me
  mkdir -p "$HOME/task" "$HOME/task-b"
  printf 'WORKTREE=%q\nRUN=%q\nBASE=HEAD\n' "$HOME/task" "$HOME/state" >"$HOME/state/task.env"
  "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
  grep -q 'agent start implementer-b .*-- -p custom --approve-for-me -c' "$HOME/commands"
  "$KIT_ROOT/modules/crew/files/herdr-crew" review --by codex >/dev/null
  grep -q 'agent start reviewer .*-- -p custom --approve-for-me -c' "$HOME/commands"
  [[ -s $HOME/state/review-1.md ]]
}
@test "positional cloud is not a cloud lane flag" {
  run env HERDR_ENV=0 "$KIT_ROOT/modules/crew/files/herdr-crew" task cloud
  [[ $status == 1 && $output == *'not running inside a Herdr pane'* ]]
}
@test "watch exact message and week old state cleanup" {
  clock_fixture
  echo '{"session_id":"session"}' | "$KIT_ROOT/modules/usage/files/usage-watch"
  echo stale >"$AGENT_KIT_USAGE_CACHE/watch/old"
  touch -d @1000000000 "$AGENT_KIT_USAGE_CACHE/watch/old"
  echo '{"session_id":"new-session"}' | "$KIT_ROOT/modules/usage/files/usage-watch"
  [[ ! -e $AGENT_KIT_USAGE_CACHE/watch/old ]]
  echo '0 0' >"$AGENT_KIT_USAGE_CACHE/watch/session"
  output=$(echo '{"session_id":"session"}' | "$KIT_ROOT/modules/usage/files/usage-watch")
  [[ $(jq -r .hookSpecificOutput.additionalContext <<<"$output") == 'Usage update: Claude 5h usage is now 83% (resets 05:33)' ]]
}
@test "statusline directory opt in and cache migration" {
  mkdir -p "$HOME/.cache/herdr-usage"
  echo '{"rate_limits":{"five_hour":{"used_percentage":25}}}' >"$HOME/.cache/herdr-usage/claude-statusline.json"
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  usage_snapshot | jq -e '.claude.five_hour.used_percentage==25'
  input='{"model":{"display_name":"Sonnet"},"workspace":{"current_dir":"/project"},"rate_limits":{"five_hour":{"used_percentage":25}}}'
  [[ $(echo "$input" | "$KIT_ROOT/modules/usage/files/claude-statusline") == 'Sonnet · 5h 25%' ]]
  [[ $(echo "$input" | STATUSLINE_SHOW_DIR=1 "$KIT_ROOT/modules/usage/files/claude-statusline") == 'Sonnet · /project · 5h 25%' ]]
}
@test "skipped binaries suppress settings references and install lists every skipped path" {
  mkdir -p "$HOME/.local" "$BATS_TEST_TMPDIR/bin"
  ln -s "$BATS_TEST_TMPDIR/bin" "$HOME/.local/bin"
  run "$KIT_ROOT/bin/agent-kit" install --modules usage --yes
  [[ $status == 0 && $output == *'Installed with 6 skipped paths'* ]]
  [[ $output == *"  $HOME/.local/bin/prompt-clock"* ]]
  [[ -z $(ls -A "$BATS_TEST_TMPDIR/bin") ]]
  jq -e '(has("statusLine")|not) and ([.hooks[]?[]?.hooks[]?.command?]|length)==0' "$HOME/.claude/settings.json"
  run "$KIT_ROOT/bin/agent-kit" update --local
  [[ $status == 0 && $output == *'Installed with 6 skipped paths'* ]]
  jq -e '(has("statusLine")|not) and ([.hooks[]?[]?.hooks[]?.command?]|length)==0' "$HOME/.claude/settings.json"
}
@test "doctor flags missing quoted HOME tilde and bare settings executables" {
  "$KIT_ROOT/bin/agent-kit" install --modules usage --yes
  rm "$HOME/.local/bin/prompt-clock" "$HOME/.local/bin/claude-statusline"
  jq '.hooks.Stop=[{hooks:[{command:"~/missing-hook"},{command:"missing-bare-hook"}]}]' "$HOME/.claude/settings.json" >"$HOME/edited"
  mv "$HOME/edited" "$HOME/.claude/settings.json"
  run "$KIT_ROOT/bin/agent-kit" doctor
  [[ $status == 1 && $output == *"MISSING settings command: $HOME/.local/bin/prompt-clock"* ]]
  [[ $output == *"MISSING settings command: $HOME/.local/bin/claude-statusline"* ]]
  [[ $output == *"MISSING settings command: $HOME/missing-hook"* && $output == *'MISSING settings command: missing-bare-hook'* ]]
}
@test "update removes only kit owned references to newly skipped scripts" {
  "$KIT_ROOT/bin/agent-kit" install --modules usage --yes
  mv "$HOME/.local/bin" "$HOME/previous-bin"
  ln -s "$HOME/previous-bin" "$HOME/.local/bin"
  jq '.hooks.Stop=[{hooks:[{command:"echo user"}]}]' "$HOME/.claude/settings.json" >"$HOME/edited"
  mv "$HOME/edited" "$HOME/.claude/settings.json"
  run "$KIT_ROOT/bin/agent-kit" update --local
  [[ $status == 0 ]]
  jq -e '(has("statusLine")|not) and .hooks.Stop[0].hooks[0].command=="echo user" and ([.hooks.UserPromptSubmit[]?.hooks[]?]|length)==0' "$HOME/.claude/settings.json"
}
@test "stow style config and backup directories work while deployed config stays protected" {
  mkdir -p "$BATS_TEST_TMPDIR/config" "$HOME/.local/state" "$BATS_TEST_TMPDIR/state"
  ln -s "$BATS_TEST_TMPDIR/config" "$HOME/.config"
  ln -s "$BATS_TEST_TMPDIR/state" "$HOME/.local/state/agent-kit"
  "$KIT_ROOT/bin/agent-kit" install --modules usage,crew --yes
  [[ -f $HOME/.config/agent-kit/state.json && -f $HOME/.config/agent-kit/config ]]
  [[ ! -e $BATS_TEST_TMPDIR/config/herdr/config.toml ]]
  [[ -n $(ls -A "$BATS_TEST_TMPDIR/state/backups") ]]
  "$KIT_ROOT/bin/agent-kit" update --local
  "$KIT_ROOT/bin/agent-kit" doctor
  "$KIT_ROOT/bin/agent-kit" uninstall
  [[ ! -e $HOME/.config/agent-kit/state.json ]]
}
@test "cache migration publishes complete data atomically and cleans a losing race" {
  mkdir -p "$HOME/.cache/herdr-usage" "$HOME/mock"
  echo '{"rate_limits":{"five_hour":{"used_percentage":25}}}' >"$HOME/.cache/herdr-usage/claude-statusline.json"
  export REAL_CP REAL_MV
  REAL_CP=$(command -v cp); REAL_MV=$(command -v mv)
  cat >"$HOME/mock/cp" <<'MOCK'
#!/usr/bin/env bash
[[ ! -e $HOME/.cache/agent-kit-usage ]] || exit 19
exec "$REAL_CP" "$@"
MOCK
  cat >"$HOME/mock/mv" <<'MOCK'
#!/usr/bin/env bash
jq -e '.rate_limits.five_hour.used_percentage==25' "$1/claude-statusline.json" >/dev/null || exit 20
if [[ ${LOSE_MIGRATION:-0} == 1 ]]; then
  mkdir -p "$HOME/.cache/agent-kit-usage"
  echo winner >"$HOME/.cache/agent-kit-usage/winner"
fi
exec "$REAL_MV" "$@"
MOCK
  chmod +x "$HOME/mock/cp" "$HOME/mock/mv"
  PATH="$HOME/mock:$PATH" bash -c 'source "$KIT_ROOT/modules/usage/files/usage-lib.sh"'
  jq -e '.rate_limits.five_hour.used_percentage==25' "$HOME/.cache/agent-kit-usage/claude-statusline.json"
  rm -rf "$HOME/.cache/agent-kit-usage"
  PATH="$HOME/mock:$PATH" LOSE_MIGRATION=1 bash -c 'source "$KIT_ROOT/modules/usage/files/usage-lib.sh"'
  [[ $(ls -A "$HOME/.cache/agent-kit-usage") == winner ]]
  [[ -z $(find "$HOME/.cache" -name '.usage-migration.*' -print) ]]
  rm -rf "$HOME/.cache/agent-kit-usage"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$HOME/mock/cp"
  PATH="$HOME/mock:$PATH" bash -c 'source "$KIT_ROOT/modules/usage/files/usage-lib.sh"'
  [[ ! -e $HOME/.cache/agent-kit-usage ]]
  [[ -z $(find "$HOME/.cache" -name '.usage-migration.*' -print) ]]
}
@test "empty overrides take precedence over configured values" {
  crew_double
  mkdir -p "$HOME/.config/agent-kit"
  printf 'CREW_IMPLEMENTER=codex\nCREW_IMPL_PROFILE=custom\nCREW_CODEX_ARGS=--approve-for-me\n' >"$HOME/.config/agent-kit/config"
  CREW_IMPL_PROFILE='' CREW_CODEX_ARGS='' "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
  grep -q 'agent start implementer --kind codex' "$HOME/commands"
  ! grep -q -- '-- -p\|--approve-for-me' "$HOME/commands"
  clock_fixture
  mkdir -p "$HOME/.local/share/cloud-runs"
  echo CLOUD_CREDIT_UNTIL=2033-05-20T03:33:20Z >>"$HOME/.config/agent-kit/config"
  printf 'time\t72.90\n' >"$HOME/.local/share/cloud-runs/balance.tsv"
  output=$(echo '{}' | CLOUD_CREDIT_UNTIL='' "$KIT_ROOT/modules/usage/files/prompt-clock")
  [[ $(jq -r .hookSpecificOutput.additionalContext <<<"$output") != *Cloud* ]]
}
@test "watch omits absent invalid and unformattable reset times" {
  clock_fixture
  for resets in null '"bad"' 999999999999999999; do
    printf '{"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":%s}}}\n' "$resets" >"$AGENT_KIT_USAGE_CACHE/claude-statusline.json"
    mkdir -p "$AGENT_KIT_USAGE_CACHE/watch"
    echo '0 0' >"$AGENT_KIT_USAGE_CACHE/watch/session"
    output=$(echo '{"session_id":"session"}' | "$KIT_ROOT/modules/usage/files/usage-watch")
    [[ $(jq -r .hookSpecificOutput.additionalContext <<<"$output") == 'Usage update: Claude 5h usage is now 85%' ]]
  done
}
@test "auto trust preserves commented headers and dotted project policies" {
  crew_double
  export CREW_IMPLEMENTER=codex CREW_CODEX_AUTO_TRUST=1
  mkdir -p "$CODEX_HOME"
  root=$(git -C "$PWD" rev-parse --path-format=absolute --git-common-dir)
  root=$(dirname "$root")
  quoted=$(jq -Rn --arg root "$root" '$root')
  for policy in "[projects.$quoted] # existing policy" "projects.$quoted.trust_level = \"untrusted\""; do
    printf '%s\n' "$policy" >"$CODEX_HOME/config.toml"
    "$KIT_ROOT/modules/crew/files/herdr-crew" up >/dev/null
    [[ $(cat "$CODEX_HOME/config.toml") == "$policy" ]]
  done
}
