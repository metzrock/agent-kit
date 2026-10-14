#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Arrow keys, mouse support and safe defaults'; }
module_deps() { echo ''; }
module_check() { [[ -d $KIT_ROOT/modules/look/files ]]; }
module_install() {
  local editor=nano
  if command -v code >/dev/null; then editor='code --wait'; fi
  settings_merge "$HOME/.claude/settings.json" "$(jq -cn --arg e "$editor" '{theme:"dark",editorMode:"normal",spinnerTipsEnabled:true,autoContinueAtUsageLimit:false,cleanupPeriodDays:90,env:{EDITOR:$e},permissions:{allow:["Bash(git status)","Bash(git log)","Bash(git diff)","Bash(ls)","Bash(jq --version)"]}}')"
}
module_uninstall() { uninstall_module look; }
