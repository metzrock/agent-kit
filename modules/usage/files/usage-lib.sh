#!/usr/bin/env bash
# Read only statusline input and optional session logs; never authentication files.
set -euo pipefail
usage_cache=${XDG_CACHE_HOME:-$HOME/.cache}/agent-kit-usage
usage_now=$(date +%s)
epoch_format() { date -d "@$1" "+$2" 2>/dev/null || date -r "$1" "+$2" 2>/dev/null || true; }
file_stamp() { stat -c '%Y:%s' "$1" 2>/dev/null || stat -f '%m:%z' "$1" 2>/dev/null; }
codex_snapshot() {
  local cached='{}' cache=$usage_cache/codex-snapshot.json now checked=0 path='' stamp='' oldstamp='' candidate='null' f latest=-1 mtime tmp
  now=$(date +%s)
  if [[ -f $cache ]]; then cached=$(jq -c 'select(type=="object")' "$cache" 2>/dev/null) || cached='{}'; fi
  [[ -n $cached ]] || cached='{}'
  checked=$(jq -r '.checked_at | if type=="number" then . else 0 end' <<<"$cached")
  [[ $checked =~ ^[0-9]+$ ]] || checked=0
  path=$(jq -r '.path | if type=="string" then . else "" end' <<<"$cached")
  # Only reuse paths discovered inside the sessions tree, never arbitrary cache paths.
  if [[ -n $path && ( $path != "$HOME/.codex/sessions/"* || $path == *'/../'* || $path != */rollout-*.jsonl ) ]]; then path=''; checked=0; fi
  oldstamp=$(jq -r '.stamp // ""' <<<"$cached")
  candidate=$(jq -c '.rate_limits // null' <<<"$cached")
  if (( now < checked || now-checked >= 60 )) || { [[ -n $path ]] && [[ ! -f $path ]]; }; then
    path=''
    # Discover once a minute, then stat only the cached file on intervening calls.
    # Only the newest file is parsed, independent of traversal order.
    while IFS= read -r -d '' f; do
      stamp=$(file_stamp "$f") || continue
      mtime=${stamp%%:*}
      if (( mtime > latest )); then latest=$mtime; path=$f; fi
    done < <(find "$HOME/.codex/sessions" -type f -name 'rollout-*.jsonl' -print0)
    checked=$now
  fi
  if [[ -n $path ]]; then
    stamp=$(file_stamp "$path") || stamp=''
    if [[ $path != $(jq -r '.path // ""' <<<"$cached") || $stamp != "$oldstamp" ]]; then
      candidate=$(tail -c 200000 "$path" 2>/dev/null | jq -Rc 'fromjson? | .. | objects | select(.limit_id?=="codex" and .primary?)' | tail -1) || candidate='null'
      [[ -n $candidate ]] || candidate='null'
    fi
  else stamp=''; candidate='null'; fi
  mkdir -p "$usage_cache"
  tmp=$(mktemp "$usage_cache/codex.XXXXXX")
  jq -cn --arg p "$path" --arg s "$stamp" --argjson checked "$checked" --argjson c "$candidate" \
    '{path:$p,stamp:$s,checked_at:$checked,rate_limits:$c}' >"$tmp"
  mv "$tmp" "$cache"
  printf '%s\n' "$candidate"
}
usage_snapshot() {
  local snapshot='{}' candidate
  if [[ -f $usage_cache/claude-statusline.json ]]; then
    snapshot=$(jq -c '{claude:.rate_limits}' "$usage_cache/claude-statusline.json" 2>/dev/null) || snapshot='{}'
  fi
  if [[ -d $HOME/.codex/sessions ]]; then
    candidate=$(codex_snapshot)
    snapshot=$(jq --argjson c "$candidate" '.codex=$c' <<<"$snapshot")
  fi
  printf '%s\n' "$snapshot"
}
usage_percent() {
  local used=$1 resets=$2
  [[ $used =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
  if [[ $resets =~ ^[0-9]+$ && $resets -le $usage_now ]]; then echo 0; else echo "${used%.*}"; fi
}
usage_values() {
  jq -r '[.claude.five_hour.used_percentage // "-",.claude.five_hour.resets_at // "-",
    .claude.seven_day.used_percentage // "-",.claude.seven_day.resets_at // "-",
    .codex.primary.used_percent // "-",.codex.primary.resets_at // "-",
    .codex.secondary.used_percent // "-",.codex.secondary.resets_at // "-"]|map(tostring)|join(" ")'
}
usage_level() {
  local used=${1:-0}
  if [[ ! $used =~ ^[0-9]+$ ]]; then echo 0
  elif (( used >= 95 )); then echo 3
  elif (( used >= 80 )); then echo 2
  elif (( used >= 50 )); then echo 1
  else echo 0; fi
}
