#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Herdr crew and workspace helpers'; }
module_deps() { echo 'lean'; }
module_check() { [[ -d $KIT_ROOT/modules/crew/files ]]; }
module_install() {
  local files=$KIT_ROOT/modules/crew/files
  local script skill
  for script in herdr-crew herdr-tidy; do link_kit_file "$files/$script" "$HOME/.local/bin/$script"; done
  for skill in herdr-crew herdr-tidy; do link_kit_file "$files/$skill-SKILL.md" "$HOME/.claude/skills/$skill/SKILL.md"; done
  link_kit_file "$files/agent-kit-crew.md" "$HOME/.claude/rules/agent-kit-crew.md"
  user_file "$files/config.toml" "$HOME/.config/herdr/config.toml"
  if command -v herdr >/dev/null; then
    local skill_file; skill_file=$(mktemp)
    herdr --skill >"$skill_file"
    if [[ ! -e $HOME/.claude/skills/herdr/SKILL.md ]]; then backup_then_write "$skill_file" "$HOME/.claude/skills/herdr/SKILL.md"; fi
    rm "$skill_file"
  fi
}
module_uninstall() { uninstall_module crew; }
