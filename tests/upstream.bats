#!/usr/bin/env bats
load helper
setup_installer() {
  common
  source "$KIT_ROOT/lib/ui.sh"
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$HOME/download-command"
printf '%s\n' "$4" >"$HOME/download-path"
printf '%s\n' 'printf ran >"$HOME/installer-ran"' >"$4"
MOCK
  chmod +x "$HOME/mock/curl"
  export PATH="$HOME/mock:$PATH"
}
@test "non-interactive upstream offers print official commands without downloading" {
  setup_installer
  run run_upstream_installer Herdr https://herdr.dev/install.sh sh https://herdr.dev/
  [[ $status == 0 && $output == *'Official command: curl -fsSL https://herdr.dev/install.sh -o '* && $output == *'interactive confirmation is required'* ]]
  [[ ! -e $HOME/download-command && ! -e $HOME/installer-ran ]]
}
@test "confirmed upstream offer downloads to a file, executes and cleans it" {
  setup_installer
  ui_confirm() { printf '%s\n' "$*" >"$HOME/prompt"; return 0; }
  run run_upstream_installer 'Claude Code' https://claude.ai/install.sh bash https://code.claude.com/docs/en/setup
  [[ $status == 0 && $output == *'https://code.claude.com/docs/en/setup'* ]]
  [[ $(cat "$HOME/installer-ran") == ran && $(cat "$HOME/prompt") == *'Claude Code installer?' ]]
  local installer
  installer=$(cat "$HOME/download-path")
  [[ $output == *"Official command: curl -fsSL https://claude.ai/install.sh -o $installer"* && $output == *"Official command: bash $installer"* ]]
  [[ $output != *' | '* && ! -e $installer ]]
}
@test "failed upstream download never executes and cleans the temporary file" {
  setup_installer
  ui_confirm() { return 0; }
  cat >"$HOME/mock/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$4" >"$HOME/download-path"
exit 7
MOCK
  run run_upstream_installer Herdr https://herdr.dev/install.sh sh https://herdr.dev/
  [[ $status == 7 && ! -e $HOME/installer-ran && ! -e $(cat "$HOME/download-path") ]]
}
