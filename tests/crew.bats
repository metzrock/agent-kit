#!/usr/bin/env bats
load helper
@test "cloud requests fail clearly without cloud-run" {
  mkdir -p "$HOME/tools"
  for tool in bash jq; do ln -s "$(command -v "$tool")" "$HOME/tools/$tool"; done
  run env PATH="$HOME/tools" "$KIT_ROOT/modules/crew/files/herdr-crew" task --cloud sample
  [[ $status == 1 && $output == *'Cloud lane unavailable'* ]]
}
@test "config is data, environment overrides it, and invalid values fail" {
  mkdir -p "$HOME/.config/agent-kit"
  printf 'CREW_IMPLEMENTER=invalid\n' >"$HOME/.config/agent-kit/config"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 1 && $output == *'must be sonnet or codex'* ]]
  run env CREW_IMPLEMENTER=sonnet HERDR_ENV=0 "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 1 && $output == *'not running inside a Herdr pane'* ]]
}
@test "two-part implementation is refused in Sonnet mode" {
  mkdir -p "$HOME/state"
  printf 'WORKTREE=%q\nRUN=%q\n' "$HOME" "$HOME/state" >"$HOME/state/task.env"
  echo spec >"$HOME/a.md"; echo spec >"$HOME/b.md"
  run env HERDR_ENV=1 CREW_STATE_DIR="$HOME/state" "$KIT_ROOT/modules/crew/files/herdr-crew" implement "$HOME/a.md" "$HOME/b.md"
  [[ $status == 1 && $output == *'Two-part implementation requires CREW_IMPLEMENTER=codex'* ]]
}

@test "default implementer starts Sonnet in a pane separate from the helper" {
  mkdir -p "$HOME/mock" "$HOME/state"
  cat >"$HOME/mock/herdr" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HOME/commands"
case "$1 $2" in
  'agent get') exit 1 ;;
  'pane layout') printf '{"result":{"layout":{"panes":[{"pane_id":"root","rect":{"width":160}}]}}}\n' ;;
  'pane split') printf '{"result":{"pane":{"pane_id":"split"}}}\n' ;;
  'agent start'|'pane report-metadata') echo '{}' ;;
  *) echo '{}' ;;
esac
MOCK
  chmod +x "$HOME/mock/herdr"
  run env PATH="$HOME/mock:$PATH" HERDR_ENV=1 HERDR_PANE_ID=root CREW_STATE_DIR="$HOME/state" "$KIT_ROOT/modules/crew/files/herdr-crew" up
  [[ $status == 0 ]]
  grep -q 'agent start implementer --kind claude --pane split.*--model sonnet --effort medium' "$HOME/commands"
  grep -q 'agent start sonnet --kind claude' "$HOME/commands"
  ! grep -q -- '--kind codex' "$HOME/commands"
}
@test "tidy moves split live agents together and never closes them" {
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/herdr" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HOME/commands"
case "$1 $2" in
  'workspace list') jq -cn --arg h "$HOME" '{result:{workspaces:[{workspace_id:"w1",focused:true,number:1,label:"project",worktree:{repo_root:$h}},{workspace_id:"w2",number:2,label:"duplicate",worktree:{repo_root:$h}}]}}' ;;
  'pane list') jq -cn --arg h "$HOME" '{result:{panes:[{pane_id:"p1",workspace_id:"w1",tab_id:"t1",cwd:$h,agent:"claude"},{pane_id:"p2",workspace_id:"w2",tab_id:"t2",cwd:$h,agent:"claude"},{pane_id:"p3",workspace_id:"w2",tab_id:"t2",cwd:$h,agent:"codex"}]}}' ;;
  'tab list') if [[ $4 == w1 ]]; then t=t1; else t=t2; fi; jq -cn --arg t "$t" '{result:{tabs:[{tab_id:$t,label:"abcdefghijklmnopqrstuvwxyz0123456789"}]}}' ;;
  'pane move') echo '{"result":{"move_result":{"created_tab":{"tab_id":"new"}}}}' ;;
  *) echo '{}' ;;
esac
MOCK
  chmod +x "$HOME/mock/herdr"
  run env PATH="$HOME/mock:$PATH" "$KIT_ROOT/modules/crew/files/herdr-tidy" --apply --close-empty
  [[ $status == 0 ]]
  grep -q 'pane move p2 --workspace w1 --new-tab' "$HOME/commands"
  grep -q 'pane move p3 --tab new --split right' "$HOME/commands"
  ! grep -q 'pane close' "$HOME/commands"
  grep -q 'workspace focus w1' "$HOME/commands"
  grep -q -- '--label abcdefghijklmnopqrstuvwxyz01234…' "$HOME/commands"
}


codex_crew() {
  mkdir -p "$HOME/mock" "$HOME/state" "$HOME/task"
  export PATH="$HOME/mock:$PATH" HERDR_ENV=1 HERDR_PANE_ID=root
  export CREW_STATE_DIR="$HOME/state" CREW_HELPER=codex CREW_IMPLEMENTER=codex
  printf 'WORKTREE=%q\nRUN=%q\nBASE=HEAD\nTASK_PANE=root\n' "$HOME/task" "$HOME/state" >"$HOME/state/task.env"
  echo spec >"$HOME/spec.md"
  cat >"$HOME/mock/herdr" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HOME/commands"
case "$1 $2" in
  'agent get')
    [[ -f $HOME/live-$3 ]] || exit 1
    kind=codex; [[ $3 != sonnet ]] || kind=claude
    jq -cn --arg kind "$kind" --arg cwd "$HOME/task" --arg pane "pane-$3" '{result:{agent:{agent:$kind,pane_id:$pane,cwd:$cwd,agent_status:"idle"}}}' ;;
  'agent start')
    [[ ${START_FAIL:-0} == 0 ]] || exit 1
    touch "$HOME/live-$3"; echo '{}' ;;
  'agent send-keys') rm -f "$HOME/live-$3"; echo '{}' ;;
  'agent prompt')
    [[ ${PROMPT_FAIL:-0} == 0 ]] || exit 1
    if [[ $4 != /clear && ${NO_REPORT:-0} == 0 ]]; then
      if [[ $4 == *'report to '* ]]; then
        report=${4#*report to }; report=${report%%[,: ]*}
        echo report >"$report"
      fi
    fi
    printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "${AGENT_STATUS:-idle}" ;;
  'agent read') [[ ${LIMIT:-0} != 1 ]] || echo 'usage limit reached' ;;
  'pane split') echo '{"result":{"pane":{"pane_id":"split"}}}' ;;
  'pane get') echo '{}' ;;
  *) echo '{}' ;;
esac
MOCK
  printf '#!/usr/bin/env bash\nexit 0\n' >"$HOME/mock/sleep"
  chmod +x "$HOME/mock/herdr" "$HOME/mock/sleep"
}

@test "helper config validates values and requires a Codex implementer" {
  run env CREW_HELPER=invalid "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 1 && $output == *'CREW_HELPER must be sonnet or codex'* ]]
  run env CREW_HELPER=codex CREW_IMPLEMENTER=sonnet "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 1 && $output == *'CREW_HELPER=codex requires CREW_IMPLEMENTER=codex'* ]]
  codex_crew
  mkdir -p "$HOME/.config/agent-kit"
  echo CREW_HELPER=invalid >"$HOME/.config/agent-kit/config"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 0 ]]
  run env -u CREW_HELPER "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 1 && $output == *'CREW_HELPER must be sonnet or codex'* ]]
}

@test "Codex only up starts just the implementer and status explains missing Sonnet" {
  codex_crew
  run "$KIT_ROOT/modules/crew/files/herdr-crew" up
  [[ $status == 0 && $output == *'not used (CREW_HELPER=codex)'* ]]
  grep -q 'agent start implementer --kind codex' "$HOME/commands"
  ! grep -q -- '--kind claude\|pane split' "$HOME/commands"
}

@test "Codex scout uses fresh agents effort and numbered reports and closes each pane" {
  codex_crew
  touch "$HOME/live-implementer"
  export CREW_SCOUT_NAME=mapper CREW_CODEX_ARGS=--approve-for-me
  run "$KIT_ROOT/modules/crew/files/herdr-crew" scout 'map the code'
  [[ $status == 0 && -s $HOME/state/scout.md && ! -e $HOME/live-mapper ]]
  grep -q 'pane split pane-implementer --direction down --cwd '"$HOME/task" "$HOME/commands"
  grep -q 'agent start mapper --kind codex.*--approve-for-me -c model_reasoning_effort="medium"' "$HOME/commands"
  ! grep -q -- '--sandbox' "$HOME/commands"
  grep -q 'The lead is planning' "$HOME/commands"
  grep -q 'pane close split' "$HOME/commands"
  run env CREW_CODEX_ARGS='' "$KIT_ROOT/modules/crew/files/herdr-crew" scout --effort high 'map again'
  [[ $status == 0 && -s $HOME/state/scout-2.md ]]
  grep -q 'model_reasoning_effort="high" --sandbox workspace-write' "$HOME/commands"
}

@test "Codex scout cleans up and preserves failures including startup and wait failures" {
  codex_crew
  touch "$HOME/live-implementer"
  for scenario in 'START_FAIL=1:1' 'PROMPT_FAIL=1:1' 'AGENT_STATUS=blocked:3' 'NO_REPORT=1:4' 'LIMIT=1:5'; do
    setting=${scenario%:*}; expected=${scenario#*:}
    run env "$setting" NO_REPORT=1 "$KIT_ROOT/modules/crew/files/herdr-crew" scout 'map'
    [[ $status == "$expected" && ! -e $HOME/live-scout ]]
    [[ $(tail -1 "$HOME/commands") == 'pane close split' ]]
  done
}

@test "Codex scouts reject model overrides and effort above high" {
  codex_crew
  run "$KIT_ROOT/modules/crew/files/herdr-crew" scout --model haiku map
  [[ $status == 1 && $output == *'--model is not supported with --by codex'* ]]
  for effort in xhigh max ultra; do
    run "$KIT_ROOT/modules/crew/files/herdr-crew" scout --effort "$effort" map
    [[ $status == 1 && $output == *'above high'* ]]
  done
  run env CREW_SCOUT_CODEX_EFFORT=xhigh "$KIT_ROOT/modules/crew/files/herdr-crew" scout map
  [[ $status == 1 && $output == *'above high'* ]]
  [[ ! -e $HOME/commands ]]
}

@test "review defaults to Codex in a Codex only crew" {
  codex_crew
  touch "$HOME/live-implementer"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" review
  [[ $status == 0 && -s $HOME/state/review-1.md && ! -e $HOME/live-reviewer ]]
  grep -q 'agent start reviewer --kind codex' "$HOME/commands"
  grep -q 'pane close pane-reviewer' "$HOME/commands"
  ! grep -q -- '--kind claude' "$HOME/commands"
}

@test "all explicit Sonnet paths require opt in and start Sonnet on demand" {
  codex_crew
  touch "$HOME/live-implementer"
  for job in implement fix scout review; do
    run "$KIT_ROOT/modules/crew/files/herdr-crew" "$job" --by sonnet "$HOME/spec.md"
    [[ $status == 1 && $output == *'CREW_HELPER=codex keeps Claude out of the crew; on a Codex usage limit, commit wip and wait for the reset (or rerun with CREW_ALLOW_SONNET=1)'* ]]
  done
  [[ ! -e $HOME/commands ]]
  for job in implement fix scout review; do
    rm -f "$HOME/live-sonnet" "$HOME/commands"
    run env CREW_ALLOW_SONNET=1 "$KIT_ROOT/modules/crew/files/herdr-crew" "$job" --by sonnet "$HOME/spec.md"
    [[ $status == 0 && -e $HOME/live-sonnet ]]
    grep -q 'agent start sonnet --kind claude' "$HOME/commands"
    grep -q 'pane split pane-implementer --direction down' "$HOME/commands"
  done
}

@test "Sonnet role file preserves punctuation and multiline notes outside launch argv" {
  codex_crew
  export CREW_HELPER=sonnet CREW_SONNET_NOTE=$'Do not update the task tracker; the lead does that.\nSecond line: (keep it).'
  run "$KIT_ROOT/modules/crew/files/herdr-crew" up
  [[ $status == 0 ]]
  grep -q -- '--append-system-prompt-file '"$HOME/state/sonnet-role.md" "$HOME/commands"
  grep -q 'Second line: (keep it).' "$HOME/state/sonnet-role.md"
  grep -q 'Do not update the task tracker; the lead does that.' "$HOME/state/sonnet-role.md"
  [[ $(cat "$HOME/state/sonnet-role.md") == *"$CREW_SONNET_NOTE" ]]
  ! grep -q 'Second line\|Do not update the task tracker' "$HOME/commands"
}

@test "explicit Sonnet scouting retains Haiku model and effort selection" {
  codex_crew
  touch "$HOME/live-implementer"
  run env CREW_ALLOW_SONNET=1 "$KIT_ROOT/modules/crew/files/herdr-crew" scout --by sonnet --model haiku --effort high map
  [[ $status == 0 && -s $HOME/state/scout-haiku.md ]]
  grep -q 'agent start sonnet --kind claude.*--model claude-haiku-5-5 --effort high' "$HOME/commands"
}
