#!/usr/bin/env bats
load helper
# Hide any real herdr; tests that need one add a stub.
no_herdr() {
  local dir out=
  IFS=: read -ra dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do [[ -x $dir/herdr ]] || out+=${out:+:}$dir; done
  export PATH=$out
}
fake_herdr() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/bin/herdr"; chmod +x "$BATS_TEST_TMPDIR/bin/herdr"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
@test "customize refuses before install" {
  run "$KIT_ROOT/bin/agent-kit" customize
  [ "$status" -ne 0 ]
}
@test "customize applies safe defaults without a terminal" {
  no_herdr; fake_herdr
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  "$KIT_ROOT/bin/agent-kit" customize </dev/null
  jq -e '.theme=="dark" and .editorMode=="normal" and .autoContinueAtUsageLimit==false' "$HOME/.claude/settings.json"
  grep -q 'prefix = "ctrl+b"' "$HOME/.config/herdr/config.toml"
  ! grep -qi vim "$HOME/.config/herdr/config.toml"
}
@test "customize does not install the look module" {
  no_herdr
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  "$KIT_ROOT/bin/agent-kit" customize </dev/null
  jq -e '.modules|index("look")==null' "$HOME/.config/agent-kit/state.json"
  jq -e '.env.EDITOR==null and .spinnerTipsEnabled==null' "$HOME/.claude/settings.json"
}
@test "customize skips Herdr when neither crew nor herdr is present" {
  no_herdr
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  "$KIT_ROOT/bin/agent-kit" customize </dev/null
  [ ! -e "$HOME/.config/herdr/config.toml" ]
}
@test "customize keeps an existing Herdr config" {
  no_herdr; fake_herdr
  "$KIT_ROOT/bin/agent-kit" install --modules base --yes
  mkdir -p "$HOME/.config/herdr"
  echo '# mine' >"$HOME/.config/herdr/config.toml"
  "$KIT_ROOT/bin/agent-kit" customize </dev/null
  [ "$(cat "$HOME/.config/herdr/config.toml")" = '# mine' ]
}
