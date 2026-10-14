#!/usr/bin/env bats
load helper
@test "customize refuses before install" {
  run "$KIT_ROOT/bin/agent-kit" customize
  [ "$status" -ne 0 ]
}
@test "customize applies safe defaults without a terminal" {
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  "$KIT_ROOT/bin/agent-kit" customize </dev/null
  jq -e '.theme=="dark" and .editorMode=="normal" and .autoContinueAtUsageLimit==false' "$HOME/.claude/settings.json"
  grep -q 'prefix = "ctrl+b"' "$HOME/.config/herdr/config.toml"
  ! grep -qi vim "$HOME/.config/herdr/config.toml"
}
@test "customize keeps an existing Herdr config" {
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  mkdir -p "$HOME/.config/herdr"
  echo '# mine' >"$HOME/.config/herdr/config.toml"
  "$KIT_ROOT/bin/agent-kit" customize </dev/null
  [ "$(cat "$HOME/.config/herdr/config.toml")" = '# mine' ]
}
