#!/usr/bin/env bash
# Third-party installs are explicit, visible and recorded only after success.
set -euo pipefail
upstream_confirm() {
  local source=$1; shift
  printf 'Source: %s\n' "$source"
  print_upstream_command "$@"
  [[ ${UPSTREAM_YES:-0} == 1 ]] || ui_confirm 'Run this upstream command?' || {
    echo 'Upstream command refused; use an interactive terminal or pass --yes.' >&2
    return 1
  }
}
upstream_require() {
  local runtime hint
  for runtime in "$@"; do
    command -v "$runtime" >/dev/null && continue
    case "$runtime" in
      npx|node) hint='Install Node.js LTS (includes npm and npx): https://nodejs.org/en/download' ;;
      python3) hint='Install Python 3, for example: sudo apt install python3' ;;
      claude) hint='Install Claude Code: https://code.claude.com/docs/en/setup' ;;
      *) hint="Install $runtime with your system package manager." ;;
    esac
    printf '%s is required. %s\n' "$runtime" "$hint" >&2
    return 127
  done
}
upstream_owned() {
  jq -e --arg id "$1" '.upstream // [] | any(.id == $id)' "$KIT_STATE" >/dev/null
}
upstream_record() {
  local id=$1 kind=$2
  # shellcheck disable=SC2016
  state_edit --arg id "$id" --arg kind "$kind" --arg m "$MODULE" \
    '.upstream = ((.upstream // [] | map(select(.id != $id))) + [{id:$id,kind:$kind,module:$m}]) | .upstream_attempts = ((.upstream_attempts // []) | map(select(.id != $id)))'
}
upstream_skill() {
  local repo=$1 pin=$2 skill=$3
  upstream_owned "$skill" && return 0
  local source=https://github.com/$repo/tree/$pin retry=0
  if jq -e --arg id "$skill" --arg source "$source" --arg m "$MODULE" \
    '.upstream_attempts // [] | any(.id == $id and .source == $source and .module == $m)' "$KIT_STATE" >/dev/null; then retry=1; fi
  if (( ! retry )) && [[ -e $HOME/.claude/skills/$skill || -L $HOME/.claude/skills/$skill || -e $HOME/.agents/skills/$skill || -L $HOME/.agents/skills/$skill ]]; then
    echo "Preserving existing skill: $skill"; return 0
  fi
  local destination=$HOME/.claude/skills/$skill/SKILL.md
  if (( retry )) && [[ -L $HOME/.claude/skills/$skill ]] && \
    [[ $(readlink -m "$HOME/.claude/skills/$skill") == "$HOME/.agents/skills/$skill" ]]; then
    # The Skills CLI links Claude's skill to its shared directory. Check both
    # parents and the shared destination, without rejecting that expected link.
    destination=$HOME/.claude/skills/$skill
  fi
  if ! safe_destination "$destination" || ! safe_destination "$HOME/.agents/skills/$skill/SKILL.md"; then
    echo "Preserving external skill directory: $skill"
    if (( retry )); then return 1; fi
    return 0
  fi
  upstream_require npx node git || return
  local cmd=(env DISABLE_TELEMETRY=1 npx --yes skills@1.7.2 add "$source" --skill "$skill" --global --agent claude-code --yes)
  upstream_confirm "https://github.com/$repo" "${cmd[@]}" || return
  # The destination was absent before the first attempt. Retain this intent if
  # the upstream CLI creates files and then fails, so a retry can finish them.
  # shellcheck disable=SC2016
  state_edit --arg id "$skill" --arg source "$source" --arg m "$MODULE" \
    '.upstream_attempts = ((.upstream_attempts // [] | map(select(.id != $id))) + [{id:$id,source:$source,module:$m,kind:"skill"}])' || return
  "${cmd[@]}" || return
  upstream_record "$skill" skill
}
upstream_plugin() {
  local repo=$1 id=$2 ref=${3:-} plugins marketplace
  marketplace=$repo${ref:+#$ref}
  upstream_owned "$id" && return 0
  upstream_require claude || return
  plugins=$(claude plugin list --json) || return
  if jq -e --arg id "$id" 'any(.. | objects; .id? == $id)' <<<"$plugins" >/dev/null; then
    echo "Preserving existing plugin: $id"; return 0
  fi
  upstream_confirm "https://github.com/$repo" claude plugin marketplace add "$marketplace" || return
  claude plugin marketplace add "$marketplace" || return
  upstream_confirm "https://github.com/$repo" claude plugin install "$id" --scope user || return
  claude plugin install "$id" --scope user || return
  upstream_record "$id" plugin
  echo 'Marketplace registration is shared and retained on uninstall.'
}
upstream_binary() {
  local id=$1 source=$2 url=$3 interpreter=$4; shift 4
  upstream_owned "$id" && return 0
  if command -v "$id" >/dev/null; then echo "Preserving existing binary: $id"; return 0; fi
  upstream_require curl "$interpreter" || return
  local extra_env=() installer result=0
  while [[ ${1:-} == --env ]]; do
    extra_env+=("${2:?missing upstream environment assignment}"); shift 2
  done
  [[ ${1:-} != -- ]] || shift
  if (( ${#extra_env[@]} )); then upstream_require env || return; fi
  installer=$(mktemp) || return
  local download=(curl -fsSL "$url" -o "$installer")
  local execute=("$interpreter" "$installer" "$@")
  if (( ${#extra_env[@]} )); then execute=(env "${extra_env[@]}" "${execute[@]}"); fi
  printf 'Source: %s\n' "$source"
  print_upstream_command "${download[@]}"
  print_upstream_command "${execute[@]}"
  if [[ ${UPSTREAM_YES:-0} != 1 ]] && ! ui_confirm 'Run this upstream installer?'; then
    rm -f "$installer"
    echo 'Upstream command refused; use an interactive terminal or pass --yes.' >&2
    return 1
  fi
  if "${download[@]}"; then "${execute[@]}" || result=$?; else result=$?; fi
  rm -f "$installer"
  (( result == 0 )) || return "$result"
  upstream_record "$id" binary
}

upstream_uninstall() {
  local row id kind
  while IFS= read -r row; do
    id=$(jq -r .id <<<"$row"); kind=$(jq -r .kind <<<"$row")
    case "$kind" in
      skill) DISABLE_TELEMETRY=1 npx --offline --yes skills@1.7.2 remove "$id" --global --agent claude-code --yes || return ;;
      impeccable) echo 'Manual step: remove ~/.claude/skills/impeccable and its Impeccable hook entries using the upstream guidance: https://github.com/pbakaus/impeccable' ;;
      apple-hig) echo 'Manual step: remove ~/.claude/skills/apple-hig/reference if no longer wanted.' ;;
      plugin) claude plugin uninstall "$id" --scope user || return ;;
      binary)
        case "$id" in
          plannotator) plannotator uninstall --yes || return ;;
          rtk) echo 'Manual step: remove ~/.local/bin/rtk; if you enabled hooks yourself, run rtk init -g --uninstall.' ;;
        esac ;;
    esac
    # shellcheck disable=SC2016
    state_edit --arg id "$id" '.upstream = ((.upstream // []) | map(select(.id != $id))) | .upstream_attempts = ((.upstream_attempts // []) | map(select(.id != $id)))'
  done < <(jq -c --arg m "$MODULE" '((.upstream // []) + (.upstream_attempts // [])) | reverse[] | select(.module == $m)' "$KIT_STATE")
  uninstall_module "$MODULE"
}
