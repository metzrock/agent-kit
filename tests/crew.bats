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


@test "full fix limit rejects round three and records an explicit override" {
  codex_crew
  touch "$HOME/live-implementer" "$HOME/state/findings-1.md" "$HOME/state/fix-2.md"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" fix "$HOME/spec.md"
  [[ $status == 1 && $output == *'full lane limit is 2'* && $output == *'--over-limit'* ]]
  [[ ! -e $HOME/state/findings-3.md ]]
  run "$KIT_ROOT/modules/crew/files/herdr-crew" fix --over-limit 'security fix remains' --by codex "$HOME/spec.md"
  [[ $status == 0 && $output == *'security fix remains'* ]]
  [[ $(cat "$HOME/state/over-limit.txt") == 'round 3: security fix remains' ]]
  [[ -f $HOME/state/findings-3.md ]]
}

@test "quick limit is one and lane changes persist with configurable limits" {
  codex_crew
  touch "$HOME/live-implementer"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" status
  [[ $status == 0 && $output == *'task lane: full'* ]]
  run "$KIT_ROOT/modules/crew/files/herdr-crew" lane quick
  [[ $status == 0 ]]
  run "$KIT_ROOT/modules/crew/files/herdr-crew" fix "$HOME/spec.md"
  [[ $status == 0 ]]
  run "$KIT_ROOT/modules/crew/files/herdr-crew" fix "$HOME/spec.md"
  [[ $status == 1 && $output == *'quick lane limit is 1'* ]]
  run env CREW_FIX_LIMIT_QUICK=2 "$KIT_ROOT/modules/crew/files/herdr-crew" fix "$HOME/spec.md"
  [[ $status == 0 ]]
  run "$KIT_ROOT/modules/crew/files/herdr-crew" lane full
  [[ $status == 0 ]]
  run env CREW_FIX_LIMIT_FULL=3 "$KIT_ROOT/modules/crew/files/herdr-crew" fix "$HOME/spec.md"
  [[ $status == 0 ]]
  run "$KIT_ROOT/modules/crew/files/herdr-crew" lane invalid
  [[ $status == 1 ]]
}

@test "cloud fixes enforce the limit before sending a job" {
  codex_crew
  printf 'LANE=cloud\nTASK_LANE=quick\n' >>"$HOME/state/task.env"
  touch "$HOME/state/findings-1.md"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" fix "$HOME/spec.md"
  [[ $status == 1 && $output == *'quick lane limit is 1'* ]]
  [[ ! -e $HOME/commands ]]
  # Deliberately fail at cloud_put, after the shared override gate.
  run "$KIT_ROOT/modules/crew/files/herdr-crew" fix --over-limit 'cloud follow-up' "$HOME/spec.md"
  [[ $output == *'over limit: cloud follow-up'* ]]
  [[ $(cat "$HOME/state/over-limit.txt") == 'round 2: cloud follow-up' ]]
}

task_start_crew() {
  codex_crew
  rm "$HOME/state/task.env"
  export CREW_WORKTREE_ROOT="$HOME/worktrees" XDG_CACHE_HOME="$HOME/cache"
  mkdir -p "$HOME/repo" "$XDG_CACHE_HOME/agent-kit-usage"
  git -C "$HOME/repo" init -q
  git -C "$HOME/repo" -c user.name=Test -c user.email=noreply@example.com commit -q --allow-empty -m initial
  cd "$HOME/repo"
  # Return a workspace and create the actual checkout, as Herdr would.
  sed -i "/case \"\$1 \$2\" in/a\\
  'worktree create') git -C \"\$4\" worktree add -q -b \"\$6\" \"\${10}\" \"\$8\"; echo '{\"result\":{\"workspace\":{\"workspace_id\":\"task\"},\"root_pane\":{\"pane_id\":\"root\"}}}';;" "$HOME/mock/herdr"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$HOME/mock/usage-status"
  chmod +x "$HOME/mock/usage-status"
}

@test "task blocks high Claude before creating worktree and anyway preserves lane and session" {
  task_start_crew
  printf '{"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":"tomorrow"}}}' >"$XDG_CACHE_HOME/agent-kit-usage/claude-statusline.json"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" task --lane quick sample
  [[ $status == 1 && $output == *'80%'* && $output == *'tomorrow'* && $output == *'--anyway'* ]]
  [[ ! -e $HOME/commands && ! -e $HOME/worktrees ]]
  run env CLAUDE_CODE_SESSION_ID=lead-session "$KIT_ROOT/modules/crew/files/herdr-crew" task --anyway --lane quick sample
  [[ $status == 0 ]]
  grep -q '^TASK_LANE=quick$' "$HOME/state/task.env"
  grep -q '^LEAD_SESSION_ID=lead-session$' "$HOME/state/task.env"
}

@test "unknown Claude never blocks and high Codex only warns" {
  task_start_crew
  printf '#!/usr/bin/env bash\necho "Claude 12%% · Codex 95%% ↻12:00"\n' >"$HOME/mock/usage-status"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" task sample
  [[ $status == 0 && $output == *'warning: Codex 5h usage is 95%'* ]]
  grep -q '^TASK_LANE=full$' "$HOME/state/task.env"
  [[ $(cat "$HOME/state"/runs/*/usage-start.tsv) == $'-\t-' ]]
}

@test "start threshold is configurable and unexpected usage-status is harmless" {
  task_start_crew
  printf '{"rate_limits":{"five_hour":{"used_percentage":79.5}}}' >"$XDG_CACHE_HOME/agent-kit-usage/claude-statusline.json"
  run env CREW_START_LIMIT=70 "$KIT_ROOT/modules/crew/files/herdr-crew" task sample
  [[ $status == 1 && $output == *'79.5%'* ]]
  printf '#!/usr/bin/env bash\necho unexpected; exit 1\n' >"$HOME/mock/usage-status"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" task sample
  [[ $status == 0 ]]
}

finish_crew() {
  codex_crew
  export XDG_STATE_HOME="$HOME/log-state" XDG_DATA_HOME="$HOME/data" XDG_CACHE_HOME="$HOME/cache"
  git -C "$HOME/task" init -q
  git -C "$HOME/task" -c user.name=Test -c user.email=noreply@example.com commit -q --allow-empty -m initial
  git -C "$HOME/task" branch -f crew/sample
  printf 'REPO=%q\nBRANCH=crew/sample\nTASK_LANE=quick\nLANE=local\nLEAD_SESSION_ID=lead-session\n' "$HOME/task" >>"$HOME/state/task.env"
  printf '12\t-\n' >"$HOME/state/usage-start.tsv"
  touch -d '10 minutes ago' "$HOME/state/usage-start.tsv"
}

@test "finish logs counts and deduplicated uncached transcript usage" {
  finish_crew
  touch "$HOME/state/scout.md" "$HOME/state/spec-b.md" "$HOME/state/findings-1.md" "$HOME/state/findings-2.md"
  printf 'MUST-FIX twice MUST-FIX\n## must-fix\n  - **MUST-FIX**: issue\n  2.) must-fix: issue\nno MUST-FIX findings\nFix every MUST-FIX\n' >"$HOME/state/review-1.md"
  echo approved >"$HOME/state/review-2.md"
  printf 'round 2: reason\n' >"$HOME/state/over-limit.txt"
  mkdir -p "$HOME/.claude/projects/project" "$HOME/custom-codex/sessions/2026/01/01" "$XDG_CACHE_HOME/agent-kit-usage"
  export CODEX_HOME="$HOME/custom-codex"
  printf '{"rate_limits":{"five_hour":{"used_percentage":24}}}' >"$XDG_CACHE_HOME/agent-kit-usage/claude-statusline.json"
  now=$(date -u +%Y-%m-%dT%H:%M:%S.123Z)
  jq -cn --arg t "$now" '{type:"assistant",timestamp:$t,message:{id:"one",usage:{input_tokens:10,cache_creation_input_tokens:20,cache_read_input_tokens:999,output_tokens:3}}}' >"$HOME/.claude/projects/project/lead-session.jsonl"
  cat "$HOME/.claude/projects/project/lead-session.jsonl" >>"$HOME/duplicate"
  cat "$HOME/duplicate" >>"$HOME/.claude/projects/project/lead-session.jsonl"
  printf '%s\n' '{"type":"assistant","timestamp":"2000-01-01T00:00:00Z","message":{"id":"old","usage":{"input_tokens":999}}}' >>"$HOME/.claude/projects/project/lead-session.jsonl"
  printf '%s\n' '{"type":"assistant","timestamp":"2999-01-01T00:00:00Z","message":{"id":"future","usage":{"input_tokens":999}}}' '{"type":"user","message":{"content":"private text"}}' >>"$HOME/.claude/projects/project/lead-session.jsonl"
  for target in task task-b other; do
    jq -cn --arg cwd "$HOME/$target" '{payload:{cwd:$cwd}}' >"$CODEX_HOME/sessions/2026/01/01/$target.jsonl"
    printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":5}}}}' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":10}}}}' >>"$CODEX_HOME/sessions/2026/01/01/$target.jsonl"
  done
  cp "$CODEX_HOME/sessions/2026/01/01/task.jsonl" "$CODEX_HOME/sessions/2026/01/01/stale.jsonl"
  touch -d '1 hour ago' "$CODEX_HOME/sessions/2026/01/01/stale.jsonl"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" finish
  [[ $status == 0 && ! -e $HOME/state/task.env ]]
  log="$XDG_STATE_HOME/herdr-crew/crew-log.tsv"
  [[ $(wc -l <"$log") == 2 ]]
  awk -F '\t' 'NR==1 {if (NF!=16 || $16!="codex_tokens") exit 1} NR==2 {if (NF!=16 || $2!="task" || $3!="sample" || $4!="quick" || $5!="local" || $6!=1 || $7!=1 || $8!=2 || $9!=2 || $10!=1 || $11!=4 || $12!=10 || $13!=12 || $14!=24 || $15!=33 || $16!=220) exit 1}' "$log"
}

@test "finish logs unknown tokens and appends without another header" {
  finish_crew
  run "$KIT_ROOT/modules/crew/files/herdr-crew" finish
  [[ $status == 0 ]]
  awk -F '\t' 'NR==2 {if ($15!="-" || $16!="-" || $6!=0 || $7!=0 || $8!=0) exit 1}' "$XDG_STATE_HOME/herdr-crew/crew-log.tsv"
  finish_crew
  run "$KIT_ROOT/modules/crew/files/herdr-crew" finish
  [[ $status == 0 ]]
  [[ $(wc -l <"$XDG_STATE_HOME/herdr-crew/crew-log.tsv") == 3 ]]
}

@test "finish still succeeds when crew log cannot be written" {
  finish_crew
  mkdir -p "$XDG_STATE_HOME/herdr-crew/crew-log.tsv"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" finish
  [[ $status == 0 && $output == *'note: could not write crew-log.tsv'* && $output == *'Task finished.'* ]]
  [[ ! -e $HOME/state/task.env ]]
}


@test "cloud and task lane flags work in either order" {
  task_start_crew
  git remote add origin https://github.com/example/project.git
  printf '#!/usr/bin/env bash\nexit 0\n' >"$HOME/mock/cloud-run"
  chmod +x "$HOME/mock/cloud-run"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" task --cloud --lane full first
  [[ $status == 0 ]]
  grep -q '^LANE=cloud$' "$HOME/state/task.env"
  grep -q '^TASK_LANE=full$' "$HOME/state/task.env"
  rm "$HOME/state/task.env"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" task --lane quick --cloud second
  [[ $status == 0 ]]
  grep -q '^LANE=cloud$' "$HOME/state/task.env"
  grep -q '^TASK_LANE=quick$' "$HOME/state/task.env"
}

@test "malformed transcripts cannot interrupt finish" {
  finish_crew
  mkdir -p "$HOME/.claude/projects/project"
  echo invalid >"$HOME/.claude/projects/project/lead-session.jsonl"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" finish
  [[ $status == 0 && $output == *'note: could not write crew-log.tsv'* ]]
  [[ ! -e $HOME/state/task.env ]]
}


@test "concurrent first finishes keep one header and both task rows" {
  finish_crew
  cp -a "$HOME/state" "$HOME/state-b"
  printf 'RUN=%q\nBRANCH=crew/second\n' "$HOME/state-b" >>"$HOME/state-b/task.env"
  git -C "$HOME/task" branch crew/second
  export CREW_TEST_FLOCK
  CREW_TEST_FLOCK=$(command -v flock)
  mkdir -p "$XDG_STATE_HOME/herdr-crew"
  mkfifo "$HOME/lock-ready"
  exec 8<>"$HOME/lock-ready"
  exec 9>"$XDG_STATE_HOME/herdr-crew/crew-log.tsv.lock"
  "$CREW_TEST_FLOCK" -x 9
  cat >"$HOME/mock/flock" <<'MOCK'
#!/usr/bin/env bash
printf 'ready\n' >"$HOME/lock-ready"
exec "$CREW_TEST_FLOCK" "$@"
MOCK
  chmod +x "$HOME/mock/flock"
  "$KIT_ROOT/modules/crew/files/herdr-crew" finish 8>&- 9>&- >"$HOME/finish-a.out" 2>&1 &
  first=$!
  CREW_STATE_DIR="$HOME/state-b" "$KIT_ROOT/modules/crew/files/herdr-crew" finish 8>&- 9>&- >"$HOME/finish-b.out" 2>&1 &
  second=$!
  # Both finishes must reach the lock while the log is still new.
  read -r -t 10 -u 8 ready
  read -r -t 10 -u 8 ready
  [[ ! -e $XDG_STATE_HOME/herdr-crew/crew-log.tsv ]]
  "$CREW_TEST_FLOCK" -u 9
  exec 9>&- 8>&-
  wait "$first"
  wait "$second"
  [[ ! -e $HOME/state/task.env && ! -e $HOME/state-b/task.env ]]
  ! grep -q 'could not write crew-log' "$HOME/finish-a.out" "$HOME/finish-b.out"
  awk -F '\t' '
    NR==1 {if (NF!=16 || $1!="finished_at") exit 1; next}
    {if (NF!=16 || $1=="finished_at") exit 1; slugs[$3]++}
    END {if (NR!=3 || slugs["sample"]!=1 || slugs["second"]!=1) exit 1}
  ' "$XDG_STATE_HOME/herdr-crew/crew-log.tsv"
}

@test "lock failure still allows finish to succeed" {
  finish_crew
  printf '#!/usr/bin/env bash\nexit 1\n' >"$HOME/mock/flock"
  chmod +x "$HOME/mock/flock"
  run "$KIT_ROOT/modules/crew/files/herdr-crew" finish
  [[ $status == 0 && $output == *'note: could not write crew-log.tsv'* ]]
  [[ ! -e $HOME/state/task.env && ! -e $XDG_STATE_HOME/herdr-crew/crew-log.tsv ]]
}
