#!/usr/bin/env bats
load helper
@test "usage windows reset and threshold levels are correct" {
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  [[ $(usage_percent 82.7 1) == 0 ]]
  [[ $(usage_percent 82.7 9999999999) == 82 ]]
  [[ -z $(usage_percent broken unknown) ]]
  [[ $(usage_level 49) == 0 && $(usage_level 50) == 1 && $(usage_level 80) == 2 && $(usage_level 95) == 3 ]]
  source "$KIT_ROOT/lib/common.sh"
  mkdir -p "$HOME/.local/share/usage-log"
  printf '10\t9999999999\t25\t9999999999\n90\t1\t5\t9999999999\n' >"$HOME/.local/share/usage-log/tasks.tsv"
  run usage_report
  [[ $status == 0 && $output == *'Task 1: 15.0 Claude 5h percentage points'* && $output == *'Task 2: unavailable'* ]]
}
@test "watch only reports rising thresholds after the first observation" {
  "$KIT_ROOT/bin/agent-kit" install --modules usage --yes
  mkdir -p "$HOME/.cache/agent-kit-usage"
  cache=$HOME/.cache/agent-kit-usage/claude-statusline.json
  echo '{"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":9999999999}}}' >"$cache"
  run bash -c 'echo "{\"session_id\":\"test-session\"}" | "$HOME/.local/bin/usage-watch"'
  [[ $status == 0 && -z $output ]]
  echo '{"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":9999999999}}}' >"$cache"
  run bash -c 'echo "{\"session_id\":\"test-session\"}" | "$HOME/.local/bin/usage-watch"'
  [[ $status == 0 && $output == *'Claude 5h 80%'* ]]
  run bash -c 'echo "{\"session_id\":\"test-session\"}" | "$HOME/.local/bin/usage-watch"'
  [[ $status == 0 && -z $output ]]
}
@test "statusline caches input and prompt-clock emits JSON and a log" {
  "$KIT_ROOT/bin/agent-kit" install --modules usage --yes
  echo '{"model":{"display_name":"Sonnet"},"rate_limits":{"five_hour":{"used_percentage":23}}}' | "$HOME/.local/bin/claude-statusline"
  echo '{"session_id":"test-session"}' | "$HOME/.local/bin/prompt-clock" | jq -e '.hookSpecificOutput.additionalContext|contains("Claude 5h 23%")'
  [[ $(wc -l <"$HOME/.local/share/usage-log/usage.tsv") == 2 ]]
}
@test "Codex session logs work under directories with spaces" {
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  mkdir -p "$HOME/.codex/sessions/a b"
  echo '{"payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":81,"resets_at":9999999999}}}}' >"$HOME/.codex/sessions/a b/rollout-test.jsonl"
  usage_snapshot | jq -e '.codex.primary.used_percent==81'
}

@test "Codex hooks parse only the newest log and reuse an unchanged snapshot" {
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  mkdir -p "$HOME/.codex/sessions/a b" "$HOME/mock"
  older=$HOME/.codex/sessions/a\ b/rollout-old.jsonl
  newer=$HOME/.codex/sessions/a\ b/rollout-new.jsonl
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":20}}}' >"$older"
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":81}}}' >"$newer"
  touch -t 202001010000 "$older"
  touch -t 202001020000 "$newer"
  export REAL_TAIL REAL_FIND
  REAL_TAIL=$(command -v tail); REAL_FIND=$(command -v find)
  cat >"$HOME/mock/tail" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} != -c ]] || printf '%s\n' "$3" >>"$HOME/parsed-files"
exec "$REAL_TAIL" "$@"
MOCK
  cat >"$HOME/mock/find" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo find >>"$HOME/discovery-calls"
exec "$REAL_FIND" "$@"
MOCK
  chmod +x "$HOME/mock/tail" "$HOME/mock/find"
  export PATH="$HOME/mock:$PATH"
  usage_snapshot | jq -e '.codex.primary.used_percent==81'
  usage_snapshot | jq -e '.codex.primary.used_percent==81'
  [[ $(wc -l <"$HOME/parsed-files") == 1 && $(cat "$HOME/parsed-files") == "$newer" ]]
  [[ $(wc -l <"$HOME/discovery-calls") == 1 ]]
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":95}}}' >"$newer"
  touch -t 202001030000 "$newer"
  usage_snapshot | jq -e '.codex.primary.used_percent==95'
  [[ $(wc -l <"$HOME/parsed-files") == 2 && $(wc -l <"$HOME/discovery-calls") == 1 ]]
}
@test "expired Codex discovery cache finds a newly created session" {
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  mkdir -p "$HOME/.codex/sessions/a b"
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":20}}}' >"$HOME/.codex/sessions/a b/rollout-old.jsonl"
  touch -t 202001010000 "$HOME/.codex/sessions/a b/rollout-old.jsonl"
  usage_snapshot | jq -e '.codex.primary.used_percent==20'
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":80}}}' >"$HOME/.codex/sessions/a b/rollout-new.jsonl"
  touch -t 202001020000 "$HOME/.codex/sessions/a b/rollout-new.jsonl"
  jq '.checked_at=0' "$usage_cache/codex-snapshot.json" >"$HOME/cache-new"
  cp "$HOME/cache-new" "$usage_cache/codex-snapshot.json"
  usage_snapshot | jq -e '.codex.primary.used_percent==80'
}
@test "Codex cache recovers from a deleted log and corrupt cache JSON" {
  source "$KIT_ROOT/modules/usage/files/usage-lib.sh"
  mkdir -p "$HOME/.codex/sessions" "$usage_cache"
  echo '{"rate_limits":{"limit_id":"codex","primary":{"used_percent":20}}}' >"$HOME/.codex/sessions/rollout-test.jsonl"
  echo invalid >"$usage_cache/codex-snapshot.json"
  usage_snapshot | jq -e '.codex.primary.used_percent==20'
  rm "$HOME/.codex/sessions/rollout-test.jsonl"
  usage_snapshot | jq -e '.codex==null'
}
