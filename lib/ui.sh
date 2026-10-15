#!/usr/bin/env bash
set -euo pipefail
ui_choose() {
  local prompt=$1 answer choice; shift
  # Callers capture stdout with $(...); gum and the prompt draw on stderr, so check that instead.
  if [[ -t 0 && -t 2 ]]; then
    if command -v gum >/dev/null; then gum choose --header "$prompt" "$@"; return; fi
    printf '%s (%s): ' "$prompt" "$*" >&2
    read -r answer || answer=''
    for choice in "$@"; do [[ $answer != "$choice" ]] || { echo "$answer"; return; }; done
  fi
  echo "$1"
}
ui_confirm() {
  [[ -t 0 && -t 1 ]] || return 1
  if command -v gum >/dev/null; then gum confirm "$1"; else
    local answer; read -r -p "$1 [y/N] " answer || return 1
    [[ $answer == y || $answer == Y ]]
  fi
}
ui_spin() {
  local title=$1; shift
  if [[ -t 1 ]] && command -v gum >/dev/null; then gum spin --title "$title" -- "$@"; else "$@"; fi
}
ui_style() {
  if [[ -t 1 ]] && command -v gum >/dev/null; then gum style --bold "$@"; else printf '%s\n' "$@"; fi
}
