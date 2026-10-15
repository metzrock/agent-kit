#!/usr/bin/env bash
# Read only statusline input and optional session logs; never authentication files.
set -euo pipefail
usage_cache=${AGENT_KIT_USAGE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/agent-kit-usage}
# Migrate cached readings once when adopting the default directory.
legacy_cache=${XDG_CACHE_HOME:-$HOME/.cache}/herdr-usage
if [[ -z ${AGENT_KIT_USAGE_CACHE:-} && ! -e $usage_cache && -d $legacy_cache ]]; then
  # Publish a complete directory with one rename. Using its basename and the
  # parent as mv's destination prevents nesting into a concurrent winner.
  migrate_usage_cache() (
    local staging parent=${usage_cache%/*} name=${usage_cache##*/}
    mkdir -p "$parent"
    staging=$(mktemp -d "$parent/.usage-migration.XXXXXX")
    trap 'rm -rf "$staging"' EXIT
    mkdir "$staging/$name"
    cp -R "$legacy_cache/." "$staging/$name/" && mv "$staging/$name" "$parent/" 2>/dev/null || true
  )
  migrate_usage_cache
fi
codex_sessions=${CODEX_HOME:-$HOME/.codex}/sessions
usage_now=$(date +%s)
epoch_format() { date -d "@$1" "+$2" 2>/dev/null || date -r "$1" "+$2" 2>/dev/null || true; }
file_stamp() { stat -c '%Y:%s' "$1" 2>/dev/null || stat -f '%m:%z' "$1" 2>/dev/null; }
codex_snapshot() {
  local candidates=() times=() index count selected found
  local cached='{}' cache=$usage_cache/codex-snapshot.json now checked=0 path='' stamp='' oldstamp='' candidate='null' f mtime tmp
  now=$(date +%s)
  if [[ -f $cache ]]; then cached=$(jq -c 'select(type=="object")' "$cache" 2>/dev/null) || cached='{}'; fi
  [[ -n $cached ]] || cached='{}'
  checked=$(jq -r '.checked_at | if type=="number" then . else 0 end' <<<"$cached")
  [[ $checked =~ ^[0-9]+$ ]] || checked=0
  path=$(jq -r '.path | if type=="string" then . else "" end' <<<"$cached")
  # Only reuse paths discovered inside the sessions tree, never arbitrary cache paths.
  if [[ -n $path && ( $path != "$codex_sessions/"* || $path == *'/../'* || $path != */rollout-*.jsonl ) ]]; then path=''; checked=0; fi
  oldstamp=$(jq -r '.stamp // ""' <<<"$cached")
  candidate=$(jq -c '.rate_limits // null' <<<"$cached")
  if (( now < checked || now-checked >= 60 )) || { [[ -n $path ]] && [[ ! -f $path ]]; }; then
    path=''; candidate='null'
    # Keep the five newest paths without whitespace-based filename splitting.
    while IFS= read -r -d '' f; do
      stamp=$(file_stamp "$f") || continue
      mtime=${stamp%%:*}
      index=0
      count=${#candidates[@]}
      while (( index < count )) && (( times[index] >= mtime )); do index=$((index+1)); done
      candidates=(${candidates[@]+"${candidates[@]:0:index}"} "$f" ${candidates[@]+"${candidates[@]:index}"})
      times=(${times[@]+"${times[@]:0:index}"} "$mtime" ${times[@]+"${times[@]:index}"})
      candidates=(${candidates[@]+"${candidates[@]:0:5}"}); times=(${times[@]+"${times[@]:0:5}"})
    done < <(find "$codex_sessions" -type f -name 'rollout-*.jsonl' -print0)
    for selected in ${candidates[@]+"${candidates[@]}"}; do
      found=$(tail -c 200000 "$selected" 2>/dev/null | jq -Rc 'fromjson? | .. | objects | select(.limit_id?=="codex" and .primary?)' | tail -1) || found=''
      if [[ -n $found ]]; then
        path=$selected; candidate=$found; oldstamp=$(file_stamp "$path")
        cached=$(jq --arg p "$path" '.path=$p' <<<"$cached")
        break
      fi
    done
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
    snapshot=$(jq -c '{claude:.rate_limits, prompt_cache:.prompt_cache, session_id:.session_id}' "$usage_cache/claude-statusline.json" 2>/dev/null) || snapshot='{}'
  fi
  if [[ -d $codex_sessions ]]; then
    candidate=$(codex_snapshot)
    snapshot=$(jq --argjson c "$candidate" '.codex=$c' <<<"$snapshot")
  fi
  if [[ -f $usage_cache/claude-statusline.json ]]; then
    snapshot=$(jq --argjson t "$(file_stamp "$usage_cache/claude-statusline.json" | cut -d: -f1)" '.claude_as_of=$t' <<<"$snapshot")
  fi
  if [[ -f $usage_cache/codex-snapshot.json ]]; then
    snapshot=$(jq --argjson t "$(jq -r '.stamp // "" | split(":")[0] | tonumber? // 0' "$usage_cache/codex-snapshot.json")" '.codex_as_of=$t' <<<"$snapshot")
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

usage_window() {
  local label=$1 used=$2 resets=$3 percent format=%a
  percent=$(usage_percent "$used" "$resets")
  [[ -n $percent ]] || return 0
  if [[ $resets =~ ^[0-9]+$ && $resets -le $usage_now ]]; then
    printf '%s 0%% (window reset)' "$label"
  else
    printf '%s %s%%' "$label" "$percent"
    [[ $label != 5h ]] || format=%H:%M
    [[ ! $resets =~ ^[0-9]+$ ]] || printf ' (resets %s)' "$(epoch_format "$resets" "$format")"
  fi
}
usage_age() {
  local taken=$1
  if [[ $taken =~ ^[0-9]+$ ]] && (( taken > 0 && usage_now-taken > ${PROMPT_CLOCK_STALE_MIN:-10}*60 )); then
    printf ' [as of %s]' "$(epoch_format "$taken" %H:%M)"
  fi
}
iso_time() {
  local value
  if [[ $# == 0 ]]; then value=$(date '+%Y-%m-%dT%H:%M:%S%z'); else value=$(epoch_format "$1" '%Y-%m-%dT%H:%M:%S%z'); fi
  printf '%s\n' "$value" | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/'
}
