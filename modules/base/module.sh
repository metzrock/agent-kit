#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Core settings and starter instructions'; }
module_deps() { echo 'git jq curl'; }
module_check() { [[ -d $KIT_ROOT/modules/base/files ]]; }
module_install() {
  local files=$KIT_ROOT/modules/base/files
  user_file "$files/config" "$KIT_CONFIG/config"
  user_file "$files/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_kit_file "$KIT_ROOT/bin/agent-kit" "$HOME/.local/bin/agent-kit"
  link_kit_file "$files/kit-interview-SKILL.md" "$HOME/.claude/skills/kit-interview/SKILL.md"
  settings_merge "$HOME/.claude/settings.json" "$(jq -cn --arg m "$MODEL" '{model:$m}')"
}
module_uninstall() { uninstall_module base; }
