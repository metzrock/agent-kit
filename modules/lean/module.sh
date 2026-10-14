#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Focused Claude subagents and medium effort'; }
module_deps() { echo ''; }
module_check() { [[ -d $KIT_ROOT/modules/lean/files ]]; }
module_install() {
  local files=$KIT_ROOT/modules/lean/files
  local agent
  for agent in implementer reviewer scoper shipper; do
    link_kit_file "$files/$agent.md" "$HOME/.claude/agents/$agent.md"
  done
  link_kit_file "$files/agent-kit-delegation.md" "$HOME/.claude/rules/agent-kit-delegation.md"
  settings_merge "$HOME/.claude/settings.json" '{"modelSettings":{"claude-opus-5-5":{"effortLevel":"medium"},"claude-sonnet-5-5":{"effortLevel":"medium"}}}'
}
module_uninstall() { uninstall_module lean; }
