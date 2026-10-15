#!/usr/bin/env bash
set -euo pipefail
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
bin/agent-kit install --modules all --yes
bin/agent-kit doctor
bin/agent-kit list --json | jq -e 'length == 9' >/dev/null
cp "$HOME/.claude/settings.json" "$HOME/settings-before.json"
bin/agent-kit install --modules all --yes
cmp "$HOME/settings-before.json" "$HOME/.claude/settings.json"
rm "$HOME/settings-before.json"
bin/agent-kit uninstall
# Only timestamped backup snapshots and their parent directories may remain.
remaining=$(find "$HOME" -type f ! -path '*/.local/state/agent-kit/backups/*')
[[ -z $remaining ]]
