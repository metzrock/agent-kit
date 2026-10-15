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
