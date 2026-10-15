#!/usr/bin/env bats
load helper
# ui_choose is always called inside $(...), so stdout is a pipe even in a real terminal.
@test "ui_choose shows the gum menu when captured from a terminal" {
  command -v script >/dev/null || skip 'script (util-linux) is not installed'
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\necho gum-picked\n' >"$HOME/bin/gum"; chmod +x "$HOME/bin/gum"
  run script -qec "PATH=$HOME/bin:\$PATH bash -c 'source \"$KIT_ROOT/lib/ui.sh\"; picked=\$(ui_choose Theme dark light); echo \"result=\$picked\"'" /dev/null
  [[ $output == *result=gum-picked* ]]
}
@test "ui_choose picks the first option without a terminal" {
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\necho gum-picked\n' >"$HOME/bin/gum"; chmod +x "$HOME/bin/gum"
  run bash -c "PATH=$HOME/bin:\$PATH; source '$KIT_ROOT/lib/ui.sh'; ui_choose Theme dark light </dev/null 2>/dev/null"
  [[ $output == dark ]]
}
