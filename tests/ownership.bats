#!/usr/bin/env bats
load helper
@test "install is idempotent and uninstall restores exact original settings" {
  mkdir -p "$HOME/.claude"
  printf '{ "model": "custom", "hooks": {}, "other": [2,1] }\n' >"$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/original"
  "$KIT_ROOT/bin/agent-kit" install --yes
  jq -e '.model=="custom"' "$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/installed"
  "$KIT_ROOT/bin/agent-kit" install --yes
  cmp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/installed"
  "$KIT_ROOT/bin/agent-kit" uninstall
  cmp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/original"
}
@test "uninstall keeps user edits and foreign hooks" {
  "$KIT_ROOT/bin/agent-kit" install --modules usage,look --yes
  jq '.theme="light" | .hooks.UserPromptSubmit += [{hooks:[{type:"command",command:"echo user"}]}] | .custom=true' "$HOME/.claude/settings.json" >"$BATS_TEST_TMPDIR/edited"
  cp "$BATS_TEST_TMPDIR/edited" "$HOME/.claude/settings.json"
  "$KIT_ROOT/bin/agent-kit" uninstall
  jq -e '.theme=="light" and .custom and (.hooks.UserPromptSubmit|length)==1 and .hooks.UserPromptSubmit[0].hooks[0].command=="echo user"' "$HOME/.claude/settings.json"
}
@test "pre-existing links are backed up and restored" {
  common
  echo original >"$HOME/original"
  ln -s "$HOME/original" "$HOME/dest"
  link_kit_file "$KIT_ROOT/LICENSE" "$HOME/dest"
  uninstall_module base
  [[ -L $HOME/dest && $(readlink "$HOME/dest") == "$HOME/original" ]]
}
@test "user-owned files are preserved on install and update" {
  mkdir -p "$HOME/.claude" "$HOME/.config/herdr" "$HOME/.config/agent-kit"
  echo custom >"$HOME/.claude/CLAUDE.md"
  echo custom >"$HOME/.config/herdr/config.toml"
  echo CREW_IMPLEMENTER=codex >"$HOME/.config/agent-kit/config"
  "$KIT_ROOT/bin/agent-kit" install --yes
  "$KIT_ROOT/bin/agent-kit" update --local
  [[ $(cat "$HOME/.claude/CLAUDE.md") == custom ]]
  [[ $(cat "$HOME/.config/herdr/config.toml") == custom ]]
  [[ $(cat "$HOME/.config/agent-kit/config") == CREW_IMPLEMENTER=codex ]]
}
@test "settings arrays preserve user order, duplicates and identical existing hooks" {
  common
  echo '{"allow":["z","a","a"]}' >"$HOME/settings.json"
  settings_merge "$HOME/settings.json" '{"allow":["a","b"]}'
  jq -e '.allow==["z","a","a","b"]' "$HOME/settings.json"
  settings_merge "$HOME/settings.json" '{"allow":["a","b"]}'
  uninstall_module base
  jq -e '.allow==["z","a","a"]' "$HOME/settings.json"
}
@test "changed symlinks and changed generated files survive uninstall" {
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  rm "$HOME/.local/bin/agent-kit"
  echo custom >"$HOME/.local/bin/agent-kit"
  echo custom >"$HOME/.claude/CLAUDE.md"
  "$KIT_ROOT/bin/agent-kit" uninstall
  [[ $(cat "$HOME/.local/bin/agent-kit") == custom ]]
  [[ $(cat "$HOME/.claude/CLAUDE.md") == custom ]]
}
@test "module removal keeps dependent modules and unrelated settings" {
  "$KIT_ROOT/bin/agent-kit" install --yes
  run "$KIT_ROOT/bin/agent-kit" uninstall lean
  [[ $status == 1 && $output == *'crew depends on lean'* ]]
  "$KIT_ROOT/bin/agent-kit" uninstall usage
  jq -e '.model=="opus" and .editorMode=="normal" and (has("hooks")|not) and (has("statusLine")|not)' "$HOME/.claude/settings.json"
}
@test "dry-run and invalid modules make no home changes" {
  "$KIT_ROOT/bin/agent-kit" install --dry-run
  run "$KIT_ROOT/bin/agent-kit" install --modules invalid
  [[ $status == 1 ]]
  [[ -z $(ls -A "$HOME") ]]
}
@test "invalid JSON is rejected without rewriting it" {
  mkdir -p "$HOME/.claude"
  echo broken >"$HOME/.claude/settings.json"
  run "$KIT_ROOT/bin/agent-kit" install --yes
  [[ $status != 0 && $(cat "$HOME/.claude/settings.json") == broken ]]
  "$KIT_ROOT/bin/agent-kit" uninstall
  [[ ! -e $HOME/.local/bin/agent-kit && ! -e $HOME/.claude/CLAUDE.md ]]
  [[ $(cat "$HOME/.claude/settings.json") == broken ]]
}
@test "backup_then_write restores the overwritten file" {
  common
  echo before >"$HOME/dest"
  backup_then_write "$KIT_ROOT/LICENSE" "$HOME/dest"
  uninstall_module base
  [[ $(cat "$HOME/dest") == before ]]
}
@test "updating a scalar preserves subsequent user changes" {
  common
  settings_merge "$HOME/settings.json" '{"theme":"dark"}'
  echo '{"theme":"light"}' >"$HOME/settings.json"
  settings_merge "$HOME/settings.json" '{"theme":"dark"}'
  uninstall_module base
  jq -e '.theme=="light"' "$HOME/settings.json"
}

@test "uninstall removes only one kit-added array occurrence" {
  common
  settings_merge "$HOME/settings.json" '{"allow":["kit"]}'
  echo '{"allow":["kit","kit"]}' >"$HOME/settings.json"
  uninstall_module base
  jq -e '.allow==["kit"]' "$HOME/settings.json"
}
@test "settings parent conflicts are rejected without destroying user values" {
  common
  echo '{"hooks":"user value"}' >"$HOME/settings.json"
  run settings_merge "$HOME/settings.json" '{"hooks":{"Stop":[{"hooks":[]}]}}'
  [[ $status != 0 ]]
  jq -e '.hooks=="user value"' "$HOME/settings.json"
}

@test "install and update preserve pre-existing scalar settings without claiming ownership" {
  mkdir -p "$HOME/.claude"
  cat >"$HOME/.claude/settings.json" <<'JSON'
{"model":"sonnet","theme":"light","editorMode":"vim","env":{"EDITOR":"custom-editor"},"spinnerTipsEnabled":false,"cleanupPeriodDays":31,"autoContinueAtUsageLimit":true}
JSON
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/original"
  "$KIT_ROOT/bin/agent-kit" install --yes --model opus
  "$KIT_ROOT/bin/agent-kit" update --local
  jq -e --slurpfile original "$BATS_TEST_TMPDIR/original" '.model==$original[0].model and .theme==$original[0].theme and .editorMode==$original[0].editorMode and .env==$original[0].env and .spinnerTipsEnabled==$original[0].spinnerTipsEnabled and .cleanupPeriodDays==$original[0].cleanupPeriodDays and .autoContinueAtUsageLimit==$original[0].autoContinueAtUsageLimit' "$HOME/.claude/settings.json"
  jq -e '[.settings[].entries[]|select(.array|not)] | all(.present==false)' "$HOME/.config/agent-kit/state.json"
  "$KIT_ROOT/bin/agent-kit" uninstall
  cmp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/original"
}
@test "explicit null and false scalar values are preserved" {
  common
  echo '{"theme":null,"spinnerTipsEnabled":false}' >"$HOME/settings.json"
  settings_merge "$HOME/settings.json" '{"theme":"dark","spinnerTipsEnabled":true,"editorMode":"normal"}'
  jq -e '.theme==null and has("theme") and .spinnerTipsEnabled==false and .editorMode=="normal"' "$HOME/settings.json"
  uninstall_module base
  jq -e '.=={theme:null,spinnerTipsEnabled:false}' "$HOME/settings.json"
}
@test "update recreates a deleted settings document with a fresh baseline" {
  "$KIT_ROOT/bin/agent-kit" install --modules look --yes
  rm "$HOME/.claude/settings.json"
  run "$KIT_ROOT/bin/agent-kit" update --local
  [[ $status == 0 && $output != *'Could not open file'* ]]
  jq -e '.model=="opus" and .theme=="dark"' "$HOME/.claude/settings.json"
  "$KIT_ROOT/bin/agent-kit" uninstall
  [[ ! -e $HOME/.claude/settings.json ]]
}
