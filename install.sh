#!/usr/bin/env bash
# Public bootstrap: resolve a release, then run its installer.
set -euo pipefail
repo=https://github.com/OWNER/agent-kit
kit_dir=$HOME/.local/share/agent-kit
for cmd in git bash; do command -v "$cmd" >/dev/null || { echo "$cmd is required" >&2; exit 1; }; done
if [[ -e $kit_dir || -L $kit_dir ]]; then
  [[ ! -L $kit_dir && -d $kit_dir/.git ]] || { echo 'Install destination is not a kit checkout' >&2; exit 1; }
  [[ $(git -C "$kit_dir" remote get-url origin) == "$repo" ]] || { echo 'Install destination has a different origin' >&2; exit 1; }
  [[ -z $(git -C "$kit_dir" status --porcelain) ]] || { echo 'Kit checkout has local changes; preserve them before updating' >&2; exit 1; }
else
  mkdir -p "$(dirname "$kit_dir")"
  git clone "$repo" "$kit_dir"
fi
git -C "$kit_dir" fetch --tags origin
release=${AGENT_KIT_REF:-}
if [[ -z $release ]]; then
  release=$(git -C "$kit_dir" tag --list 'v[0-9]*' --sort=-version:refname | head -1)
fi
[[ -n $release ]] || { echo 'No kit release tags found' >&2; exit 1; }
git -C "$kit_dir" checkout --detach "$release"
exec bash "$kit_dir/bin/agent-kit" install "$@"
