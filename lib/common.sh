#!/usr/bin/env bash
# jq programs passed to state_edit intentionally use literal jq variables.
# shellcheck disable=SC2016
set -euo pipefail
KIT_CONFIG=$HOME/.config/agent-kit
KIT_STATE=$KIT_CONFIG/state.json
KIT_BACKUPS=$HOME/.local/state/agent-kit/backups
MODULE=base
fail() { printf 'agent-kit: %s\n' "$*" >&2; exit 1; }
state_edit() {
  local tmp; tmp=$(mktemp "$KIT_CONFIG/state.XXXXXX")
  if jq "$@" "$KIT_STATE" >"$tmp"; then mv "$tmp" "$KIT_STATE"; else rm -f "$tmp"; return 1; fi
}
# Refuse to traverse user-owned directory links below HOME.
safe_destination() {
  local dest=$1 parent resolved
  # Kit bookkeeping and the personal config overlay support stow-style parents.
  case "$dest" in "$KIT_CONFIG"|"$KIT_CONFIG/"*|"$KIT_BACKUPS"|"$KIT_BACKUPS/"*) return 0 ;; esac
  parent=$(dirname "$dest")
  while [[ $parent == "$HOME/"* ]]; do
    if [[ -L $parent ]]; then
      resolved=$(cd "$parent" 2>/dev/null && pwd -P) || resolved=''
      if [[ $resolved != "$KIT_ROOT" && $resolved != "$KIT_ROOT/"* ]]; then
        printf 'Skipping user-owned symlink directory: %s (destination: %s)\n' "$parent" "$dest" >&2
        return 1
      fi
    fi
    parent=$(dirname "$parent")
  done
}
writable_destination() {
  safe_destination "$1" && return 0
  if [[ -f $KIT_STATE ]] && safe_destination "$KIT_STATE"; then
    state_edit --arg p "$1" '.skipped = (((.skipped // []) + [$p])|unique)'
  fi
  return 1
}
ensure_dir() {
  [[ -d $1 ]] && return 0
  [[ ! -e $1 && ! -L $1 ]] || fail "not a directory: $1"
  local parent; parent=$(dirname "$1")
  ensure_dir "$parent"
  mkdir "$1"
  state_edit --arg p "$1" '.dirs += [$p]'
}
acquire_lock() {
  safe_destination "$KIT_CONFIG/.lock" || fail "agent-kit state directory is user-owned"
  mkdir -p "$KIT_CONFIG"
  mkdir "$KIT_CONFIG/.lock" 2>/dev/null || fail 'another agent-kit command is running (remove a stale .lock directory after checking)'
  trap 'rmdir "$KIT_CONFIG/.lock"; if [[ ! -f $KIT_STATE ]]; then rmdir "$KIT_CONFIG" "$HOME/.config" 2>/dev/null || true; fi' EXIT
}
state_init() {
  safe_destination "$KIT_STATE" || fail "agent-kit state directory is user-owned"
  command -v jq >/dev/null || fail 'jq is required; install jq first'
  if [[ ! -f $KIT_STATE ]]; then
    mkdir -p "$KIT_CONFIG"
    printf '%s\n' '{"version":1,"modules":[],"files":[],"settings":[],"dirs":[]}' >"$KIT_STATE"
  fi
  jq -e '.version == 1 and (.files|type == "array")' "$KIT_STATE" >/dev/null || fail 'invalid state file'
}
backup_file() {
  safe_destination "$KIT_BACKUPS/file" || fail "backup directory is user-owned"
  mkdir -p "$KIT_BACKUPS"
  local backup; backup=$(mktemp "$KIT_BACKUPS/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
  rm "$backup"
  cp -P "$1" "$backup"
  printf '%s\n' "$backup"
}
record_file() {
  state_edit --arg m "$MODULE" --arg p "$1" --arg kind "$2" --arg v "$3" --arg b "$4" \
    '.files += [{module:$m,path:$p,kind:$kind,value:$v,backup:$b}]'
}
link_kit_file() {
  local source=$1 dest=$2 backup=''
  writable_destination "$dest" || return 0
  [[ -f $source ]] || fail "missing kit file: $source"
  if jq -e --arg p "$dest" '.files[] | select(.path==$p)' "$KIT_STATE" >/dev/null; then
    [[ -L $dest && $(readlink "$dest") == "$source" ]] || printf 'Preserving changed file: %s\n' "$dest" >&2
    return 0
  fi
  ensure_dir "$(dirname "$dest")"
  if [[ -e $dest || -L $dest ]]; then backup=$(backup_file "$dest"); rm "$dest"; fi
  ln -s "$source" "$dest"
  record_file "$dest" link "$source" "$backup"
}
backup_then_write() {
  local source=$1 dest=$2 backup='' snapshot
  writable_destination "$dest" || return 0
  ensure_dir "$(dirname "$dest")"
  if [[ -e $dest || -L $dest ]]; then backup=$(backup_file "$dest"); rm "$dest"; fi
  cp "$source" "$dest"
  snapshot=$(backup_file "$dest")
  record_file "$dest" copy "$snapshot" "$backup"
}
user_file() {
  [[ -e $2 || -L $2 ]] || backup_then_write "$1" "$2"
}
settings_merge() {
  local dest=$1 patch=$2 original='' tmp journal result
  writable_destination "$dest" || return 0
  [[ ! -L $dest ]] || fail 'settings symlinks are not supported; use a regular settings file'
  ensure_dir "$(dirname "$dest")"
  if [[ ! -e $dest ]]; then
    # A deleted document has a fresh ownership baseline when update recreates it.
    state_edit --arg p "$dest" '.settings |= map(select(.path!=$p))'
  fi
  if ! jq -e --arg p "$dest" '.settings[] | select(.path==$p)' "$KIT_STATE" >/dev/null; then
    if [[ -e $dest ]]; then
      jq -e 'type=="object"' "$dest" >/dev/null || fail "settings must be a JSON object: $dest"
      original=$(backup_file "$dest")
    else printf '{}\n' >"$dest"; fi
    state_edit --arg p "$dest" --arg b "$original" '.settings += [{path:$p,original:$b,entries:[]}]'
  fi
  journal=$(jq -c --arg p "$dest" '.settings[]|select(.path==$p)|.entries' "$KIT_STATE")
  result=$(jq --arg home "$HOME" --argjson skipped "$(jq ' .skipped // []' "$KIT_STATE")" --arg mode merge --arg module "$MODULE" --argjson patch "$patch" --argjson journal "$journal" -f "$KIT_ROOT/lib/settings.jq" "$dest") || return
  tmp=$(mktemp "${dest}.XXXXXX")
  jq -S '.document' <<<"$result" >"$tmp"
  if ! cmp -s "$dest" "$tmp"; then backup_file "$dest" >/dev/null; cat "$tmp" >"$dest"; fi
  rm "$tmp"
  state_edit --arg p "$dest" --argjson entries "$(jq '.entries' <<<"$result")" \
    '(.settings[]|select(.path==$p)|.entries)=$entries'
}
uninstall_module() {
  local m=$1 row path value backup kind original result tmp
  while IFS= read -r row; do
    path=$(jq -r .path <<<"$row"); value=$(jq -r .value <<<"$row")
    backup=$(jq -r .backup <<<"$row"); kind=$(jq -r .kind <<<"$row")
    safe_destination "$path" || continue
    if { [[ $kind == link && -L $path && $(readlink "$path") == "$value" ]]; } ||
       { [[ $kind == copy && -f $path && ! -L $path ]] && cmp -s "$path" "$value"; }; then
      rm "$path"
      [[ -z $backup ]] || cp -P "$backup" "$path"
    else printf 'Preserving changed file: %s (backup: %s)\n' "$path" "${backup:-none}" >&2; fi
  done < <(jq -c --arg m "$m" '.files|reverse[]|select(.module==$m)' "$KIT_STATE")
  while IFS= read -r row; do
    path=$(jq -r .path <<<"$row"); original=$(jq -r .original <<<"$row")
    safe_destination "$path" || continue
    [[ -f $path ]] || continue
    result=$(jq --arg home "$HOME" --argjson skipped '[]' --arg mode remove --arg module "$m" --argjson patch '{}' --argjson journal "$(jq .entries <<<"$row")" -f "$KIT_ROOT/lib/settings.jq" "$path")
    tmp=$(mktemp "${path}.XXXXXX"); jq -S .document <<<"$result" >"$tmp"
    if [[ $(jq '.entries|length' <<<"$result") == 0 ]]; then
      if [[ -n $original ]] && jq -e --slurpfile old "$original" '. == $old[0]' "$tmp" >/dev/null; then
        cat "$original" >"$path"
      elif [[ -z $original && $(jq 'length' "$tmp") == 0 ]]; then rm "$path"
      else cat "$tmp" >"$path"; fi
    else cat "$tmp" >"$path"; fi
    rm "$tmp"
    state_edit --arg p "$path" --argjson e "$(jq .entries <<<"$result")" '(.settings[]|select(.path==$p)|.entries)=$e'
  done < <(jq -c '.settings[]' "$KIT_STATE")
  state_edit --arg m "$m" '.files |= map(select(.module!=$m)) | .modules -= [$m]'
}
cleanup_state() {
  local dir
  while IFS= read -r dir; do safe_destination "$dir" && rmdir "$dir" 2>/dev/null || true; done < <(jq -r '.dirs|reverse[]' "$KIT_STATE")
  if [[ $(jq '.modules|length' "$KIT_STATE") == 0 ]]; then
    rm "$KIT_STATE"
    rmdir "$KIT_CONFIG" "$HOME/.config" 2>/dev/null || true
  fi
}
config_value() {
  local key=$1 fallback=$2 line
  if [[ -f $KIT_CONFIG/config ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line != "$key="* ]] || { printf '%s\n' "${line#*=}"; return; }
    done <"$KIT_CONFIG/config"
  fi
  printf '%s\n' "$fallback"
}

usage_report() {
  local log=${XDG_DATA_HOME:-$HOME/.local/share}/usage-log/tasks.tsv
  if [[ ! -s $log ]]; then echo 'No finished crew tasks with usage snapshots yet.'; return; fi
  awk -F '\t' '
    { n++; if ($1 ~ /^[0-9.]+$/ && $3 ~ /^[0-9.]+$/ && $2 ~ /^[0-9]+$/ && $2==$4 && $3>=$1)
        printf "Task %d: %.1f Claude 5h percentage points\n", n, $3-$1;
      else printf "Task %d: unavailable (missing snapshot or window reset)\n", n }
  ' "$log"
}

run_upstream_installer() {
  local name=$1 url=$2 interpreter=$3 docs=$4 installer result=0
  printf '%s official installation: %s\n' "$name" "$docs"
  printf 'Official command: curl -fsSL %s | %s\n' "$url" "$interpreter"
  if ! ui_confirm "Download and run the official $name installer?"; then
    echo 'Installer not run; interactive confirmation is required even with --yes.'
    return 0
  fi
  installer=$(mktemp)
  if curl -fsSL "$url" -o "$installer"; then
    "$interpreter" "$installer" || result=$?
  else result=$?; fi
  rm -f "$installer"
  return "$result"
}
