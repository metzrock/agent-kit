#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Design skills and Apple interface guidelines'; }
module_deps() { echo 'base'; }
module_check() { upstream_require npx node git python3; }
module_install() {
  install_impeccable || return
  upstream_skill kunchenguid/lavish-axi 224f40719d74c15897cfec0c3d67a0dce869ba5f lavish || return
  install_apple_hig || return
}
module_uninstall() { upstream_uninstall; }

install_impeccable() {
  upstream_owned impeccable && return 0
  if [[ -e $HOME/.claude/skills/impeccable || -L $HOME/.claude/skills/impeccable ]]; then
    echo 'Preserving existing skill: impeccable'; return 0
  fi
  if ! safe_destination "$HOME/.claude/skills/impeccable/SKILL.md"; then
    echo 'Preserving external skill directory: impeccable'; return 0
  fi
  upstream_require npx node || return
  local cmd=(env DISABLE_TELEMETRY=1 npx --yes impeccable@4.5.2 install -y --providers=claude --scope=global)
  upstream_confirm https://github.com/pbakaus/impeccable "${cmd[@]}" || return
  "${cmd[@]}" || return
  upstream_record impeccable impeccable
}
install_apple_hig() {
  upstream_owned apple-hig && return 0
  local dest=$HOME/.claude/skills/apple-hig
  local skill_source=$KIT_ROOT/modules/design/files/apple-hig-SKILL.md
  # A failed fetch leaves kit-owned links; recognise them when retrying.
  if [[ -e $dest || -L $dest ]]; then
    if [[ ! -L $dest/SKILL.md || $(readlink "$dest/SKILL.md") != "$skill_source" ]]; then
      echo 'Preserving existing skill: apple-hig'; return 0
    fi
  fi
  if ! safe_destination "$dest/reference/INDEX.md"; then
    echo 'Preserving external skill directory: apple-hig'; return 0
  fi
  upstream_require python3 || return
  local cmd=(python3 "$KIT_ROOT/modules/design/files/fetch_hig.py" --output "$dest/reference")
  upstream_confirm https://developer.apple.com/design/human-interface-guidelines "${cmd[@]}" || return
  link_kit_file "$KIT_ROOT/modules/design/files/apple-hig-SKILL.md" "$dest/SKILL.md" || return
  link_kit_file "$KIT_ROOT/modules/design/files/fetch_hig.py" "$dest/fetch_hig.py" || return
  "${cmd[@]}" || return
  upstream_record apple-hig apple-hig
}
