#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Local time and usage awareness'; }
module_deps() { echo ''; }
module_check() { [[ -d $KIT_ROOT/modules/usage/files ]]; }
module_install() {
  local files=$KIT_ROOT/modules/usage/files
  local script
  for script in claude-statusline usage-status prompt-clock usage-watch usage-lib.sh; do
    link_kit_file "$files/$script" "$HOME/.local/bin/$script"
  done
  link_kit_file "$files/agent-kit-usage.md" "$HOME/.claude/rules/agent-kit-usage.md"
  # shellcheck disable=SC2016 # HOME must expand when Claude runs the hook.
  settings_merge "$HOME/.claude/settings.json" '{"statusLine":{"type":"command","command":"\"$HOME/.local/bin/claude-statusline\""},"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"\"$HOME/.local/bin/prompt-clock\""}]}],"PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"\"$HOME/.local/bin/usage-watch\""}]}]}}'
}
module_uninstall() { uninstall_module usage; }
