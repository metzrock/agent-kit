#!/usr/bin/env bats
load helper

setup_upstream() {
  common
  source "$KIT_ROOT/lib/ui.sh"
  source "$KIT_ROOT/lib/upstream.sh"
  MODULE=writing
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/npx" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/commands"
exit "${MOCK_EXIT:-0}"
MOCK
  chmod +x "$HOME/mock/npx"
  export PATH="$HOME/mock:$PATH"
}
@test "JSON list offers third-party modules with one-line descriptions" {
  run "$KIT_ROOT/bin/agent-kit" list --json
  [[ $status == 0 ]]
  jq -e 'length == 9 and ([.[].name] | contains(["plannotator","design","writing","devtools"])) and all(.[]; .description | length > 0 and (contains("\n") | not))' <<<"$output"
}
@test "all excludes third-party installs and explicit modules remain selectable" {
  run "$KIT_ROOT/bin/agent-kit" install --modules all --dry-run
  [[ $status == 0 && $output != *plannotator* && $output != *devtools* ]]
  run "$KIT_ROOT/bin/agent-kit" install --modules writing,design --dry-run
  [[ $status == 0 && $output == *'base writing design'* ]]
}
@test "upstream skill refuses non-TTY without yes and makes no network command" {
  setup_upstream
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status != 0 && $output == *'Source: https://github.com/blader/humanizer'* && $output == *'Official command:'* && $output == *'refused'* ]]
  [[ ! -e $HOME/commands ]]
  ! upstream_owned humanizer
}
@test "yes runs pinned official skill command double once and records ownership" {
  setup_upstream
  UPSTREAM_YES=1
  run upstream_skill blader/humanizer 225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8 humanizer
  [[ $status == 0 ]]
  [[ $(cat "$HOME/commands") == '--yes skills@1.7.2 add https://github.com/blader/humanizer/tree/225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8 --skill humanizer --global --agent claude-code --yes' ]]
  upstream_owned humanizer
  upstream_skill blader/humanizer ignored humanizer
  [[ $(wc -l <"$HOME/commands") == 1 ]]
}
@test "failed upstream command is not recorded and is retryable" {
  setup_upstream
  UPSTREAM_YES=1
  export MOCK_EXIT=7
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 7 ]]
  ! upstream_owned humanizer
  export MOCK_EXIT=0
  upstream_skill blader/humanizer deadbeef humanizer
  upstream_owned humanizer
}
@test "existing skill is preserved and never claimed for uninstall" {
  setup_upstream
  UPSTREAM_YES=1
  mkdir -p "$HOME/.claude/skills/humanizer"
  upstream_skill blader/humanizer deadbeef humanizer
  [[ ! -e $HOME/commands ]]
  ! upstream_owned humanizer
}
@test "upstream uninstall removes only recorded module items with offline CLI" {
  setup_upstream
  UPSTREAM_YES=1
  upstream_skill blader/humanizer deadbeef humanizer
  upstream_record other skill
  MODULE=design
  upstream_record design-item skill
  MODULE=writing
  upstream_uninstall
  [[ $(tail -2 "$HOME/commands") == *'--offline --yes skills@1.7.2 remove humanizer --global --agent claude-code --yes'* ]]
  ! upstream_owned humanizer
  upstream_owned design-item
}
@test "binary installer shows pin, runs double and cleans temporary download" {
  setup_upstream
  UPSTREAM_YES=1
  cat >"$HOME/mock/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$4" >"$HOME/download-path"
printf '%s\n' 'printf "%s\n" "$*" >"$HOME/binary-args"' >"$4"
MOCK
  chmod +x "$HOME/mock/curl"
  run upstream_binary test-binary https://example.com https://example.com/install.sh bash --version v1.2.3 --minimal
  [[ $status == 0 && $output == *'--version v1.2.3 --minimal'* ]]
  [[ $(cat "$HOME/binary-args") == '--version v1.2.3 --minimal' ]]
  [[ ! -e $(cat "$HOME/download-path") ]]
  upstream_owned test-binary
}
@test "plugin install uses native commands and uninstall retains shared marketplace" {
  setup_upstream
  UPSTREAM_YES=1
  cat >"$HOME/mock/claude" <<'MOCK'
#!/usr/bin/env bash
if [[ $* == 'plugin list --json' ]]; then echo "${MOCK_PLUGINS:-[]}"; else printf '%s\n' "$*" >>"$HOME/commands"; fi
MOCK
  chmod +x "$HOME/mock/claude"
  upstream_plugin cloudflare/skills cloudflare@cloudflare
  upstream_owned cloudflare@cloudflare
  upstream_uninstall
  [[ $(cat "$HOME/commands") == $'plugin marketplace add cloudflare/skills\nplugin install cloudflare@cloudflare --scope user\nplugin uninstall cloudflare@cloudflare --scope user' ]]
}
@test "existing plugin is not claimed" {
  setup_upstream
  UPSTREAM_YES=1
  cat >"$HOME/mock/claude" <<'MOCK'
#!/usr/bin/env bash
echo '[{"id":"cloudflare@cloudflare"}]'
MOCK
  chmod +x "$HOME/mock/claude"
  upstream_plugin cloudflare/skills cloudflare@cloudflare
  ! upstream_owned cloudflare@cloudflare
}
@test "interview gives install hint when claude is missing" {
  mkdir -p "$HOME/mock"
  ln -s "$(command -v bash)" "$HOME/mock/bash"
  ln -s "$(command -v dirname)" "$HOME/mock/dirname"
  run env PATH="$HOME/mock" "$KIT_ROOT/bin/agent-kit" interview
  [[ $status != 0 && $output == *'https://claude.ai/install.sh'* ]]
}
@test "interview launches Sonnet with the skill command" {
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/claude" <<'MOCK'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
MOCK
  chmod +x "$HOME/mock/claude"
  run env PATH="$HOME/mock:$PATH" "$KIT_ROOT/bin/agent-kit" interview
  [[ $status == 0 && $output == $'<--model>\n<sonnet>\n</kit-interview>' ]]
}
setup_git() {
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/git" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$HOME/git-commands"
if [[ $1 == clone ]]; then
  mkdir -p "$3/.git" "$3/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >"$HOME/kit-args"' >"$3/bin/agent-kit"
elif [[ $* == *'remote get-url origin'* ]]; then echo "${MOCK_ORIGIN:-https://github.com/OWNER/agent-kit}"
elif [[ $* == *'status --porcelain'* ]]; then printf '%s' "${MOCK_DIRTY:-}"
elif [[ $* == *'tag --list'* ]]; then printf 'v2.0.0\nv1.0.0\n'
fi
MOCK
  chmod +x "$HOME/mock/git"
  export PATH="$HOME/mock:$PATH"
}
@test "bootstrap clones latest release then safely reruns with fake git" {
  setup_git
  run bash "$KIT_ROOT/install.sh" --modules base --yes
  [[ $status == 0 && $(cat "$HOME/kit-args") == 'install --modules base --yes' ]]
  [[ $(cat "$HOME/git-commands") == *'checkout --detach v2.0.0'* ]]
  run bash "$KIT_ROOT/install.sh" --model sonnet
  [[ $status == 0 && $(cat "$HOME/kit-args") == 'install --model sonnet' ]]
  [[ $(rg -c '^clone ' "$HOME/git-commands") == 1 ]]
}
@test "bootstrap respects pin and refuses dirty or foreign destinations" {
  setup_git
  run env AGENT_KIT_REF=v1.0.0 bash "$KIT_ROOT/install.sh"
  [[ $status == 0 && $(cat "$HOME/git-commands") == *'checkout --detach v1.0.0'* ]]
  export MOCK_DIRTY=modified
  run bash "$KIT_ROOT/install.sh"
  [[ $status != 0 && $output == *'local changes'* ]]
  unset MOCK_DIRTY
  export MOCK_ORIGIN=https://example.com/other
  run bash "$KIT_ROOT/install.sh"
  [[ $status != 0 && $output == *'different origin'* ]]
}
@test "Apple fetcher conversion and fetch failures work without network" {
  run env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$KIT_ROOT/tests" -p test_hig.py -q
  [[ $status == 0 ]]
}

@test "CLI yes authorizes writing module commands and full uninstall dispatches upstream removal" {
  setup_upstream
  cat >"$HOME/mock/claude" <<'MOCK'
#!/usr/bin/env bash
if [[ $* == 'plugin list --json' ]]; then echo '[]'; else printf '%s\n' "$*" >>"$HOME/commands"; fi
MOCK
  chmod +x "$HOME/mock/claude"
  run "$KIT_ROOT/bin/agent-kit" install --modules writing --yes
  [[ $status == 0 && $output == *'Installed: base writing'* ]]
  [[ $(wc -l <"$HOME/commands") == 5 ]]
  run "$KIT_ROOT/bin/agent-kit" uninstall
  [[ $status == 0 ]]
  [[ $(cat "$HOME/commands") == *'plugin uninstall i-have-adhd@i-have-adhd --scope user'* ]]
  [[ $(cat "$HOME/commands") == *'--offline --yes skills@1.7.2 remove humanizer'* ]]
  [[ ! -f $HOME/.config/agent-kit/state.json ]]
}

@test "skill installs preserve external parent directories" {
  setup_upstream
  UPSTREAM_YES=1
  mkdir -p "$HOME/external" "$HOME/.claude"
  ln -s "$HOME/external" "$HOME/.claude/skills"
  upstream_skill blader/humanizer deadbeef humanizer
  [[ ! -e $HOME/commands ]]
  ! upstream_owned humanizer
}
@test "failed upstream removal retains ownership for retry" {
  setup_upstream
  UPSTREAM_YES=1
  upstream_skill blader/humanizer deadbeef humanizer
  export MOCK_EXIT=7
  run upstream_uninstall
  [[ $status == 7 ]]
  upstream_owned humanizer
}


mock_claude() {
  cat >"$HOME/mock/claude" <<'MOCK'
#!/usr/bin/env bash
if [[ $* == 'plugin list --json' ]]; then echo '[]'; else printf '%s\n' "$*" >>"$HOME/commands"; fi
MOCK
  chmod +x "$HOME/mock/claude"
}
@test "failed Apple fetch retries kit-owned links and records design only after success" {
  setup_upstream
  cat >"$HOME/mock/python3" <<'MOCK'
#!/usr/bin/env bash
printf 'fetch\n' >>"$HOME/fetch-attempts"
[[ ${MOCK_FETCH_EXIT:-0} == 0 ]] || exit "$MOCK_FETCH_EXIT"
mkdir -p "$3"
printf '# Apple guidelines\n' >"$3/INDEX.md"
MOCK
  chmod +x "$HOME/mock/python3"
  export MOCK_FETCH_EXIT=9
  run "$KIT_ROOT/bin/agent-kit" install --modules design --yes
  [[ $status == 9 && $output == *'Failed/skipped module: design'* ]]
  [[ -L $HOME/.claude/skills/apple-hig/SKILL.md ]]
  ! upstream_owned apple-hig
  jq -e '(.modules|index("design")) == null and (.pending_modules|index("design")) != null' "$KIT_STATE"
  run "$KIT_ROOT/bin/agent-kit" list --json
  jq -e '.[] | select(.name == "design") | .installed == false' <<<"$output"
  export MOCK_FETCH_EXIT=0
  run "$KIT_ROOT/bin/agent-kit" install --modules design --yes
  [[ $status == 0 && $output == *'Installed: base design'* ]]
  [[ $(wc -l <"$HOME/fetch-attempts") == 2 && -f $HOME/.claude/skills/apple-hig/reference/INDEX.md ]]
  upstream_owned apple-hig
  jq -e '(.modules|index("design")) != null and (.pending_modules|index("design")) == null' "$KIT_STATE"
}
@test "existing user Apple skill stays untouched" {
  setup_upstream
  source "$KIT_ROOT/modules/design/module.sh"
  MODULE=design
  UPSTREAM_YES=1
  mkdir -p "$HOME/.claude/skills/apple-hig"
  printf 'user instructions\n' >"$HOME/.claude/skills/apple-hig/SKILL.md"
  install_apple_hig
  [[ $(cat "$HOME/.claude/skills/apple-hig/SKILL.md") == 'user instructions' ]]
  ! upstream_owned apple-hig
}
@test "refused module is not listed installed and its pending state can be cleaned up" {
  setup_upstream
  mock_claude
  # Also repair an installed row left by the earlier broken installer.
  state_edit '.modules=["writing"]'
  run "$KIT_ROOT/bin/agent-kit" install --modules writing
  [[ $status != 0 && $output == *'refused'* && $output == *'Failed/skipped module: writing'* ]]
  [[ ! -e $HOME/commands ]]
  jq -e '(.modules|index("writing")) == null and (.pending_modules|index("writing")) != null' "$KIT_STATE"
  run "$KIT_ROOT/bin/agent-kit" list --json
  jq -e '.[] | select(.name == "writing") | .installed == false' <<<"$output"
  run "$KIT_ROOT/bin/agent-kit" uninstall base
  [[ $status != 0 && $output == *'uninstall dependent modules'* ]]
  run "$KIT_ROOT/bin/agent-kit" uninstall
  [[ $status == 0 && ! -f $KIT_STATE ]]
}
@test "partial failed module stops immediately and full uninstall recovers successful items" {
  setup_upstream
  mock_claude
  cat >"$HOME/mock/npx" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/commands"
[[ $* != *'--skill grill-me'* ]] || exit 7
MOCK
  chmod +x "$HOME/mock/npx"
  run "$KIT_ROOT/bin/agent-kit" install --modules writing --yes
  [[ $status == 7 && $output == *'Failed/skipped module: writing'* ]]
  upstream_owned humanizer
  ! upstream_owned grill-me
  [[ $(wc -l <"$HOME/commands") == 2 ]]
  jq -e '(.modules|index("writing")) == null' "$KIT_STATE"
  run "$KIT_ROOT/bin/agent-kit" uninstall
  [[ $status == 0 && ! -f $KIT_STATE ]]
  [[ $(tail -1 "$HOME/commands") == '--offline --yes skills@1.7.2 remove humanizer --global --agent claude-code --yes' ]]
}

hide_runtime() {
  command() {
    if [[ ${1:-} == -v && ${2:-} == "$MISSING_RUNTIME" ]]; then return 1; fi
    builtin command "$@"
  }
  ui_confirm() { echo 'unexpected confirmation'; return 0; }
}
@test "missing npx and Node give installation hints before any confirmation" {
  setup_upstream
  hide_runtime
  MISSING_RUNTIME=npx
  run -127 upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 127 && $output == *'npx is required'* && $output == *'Node.js LTS'* && $output != *'Official command:'* && $output != *'unexpected confirmation'* ]]
  MISSING_RUNTIME=node
  run -127 upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 127 && $output == *'node is required'* && $output != *'unexpected confirmation'* ]]
  [[ ! -e $HOME/commands ]]
}
@test "design checks Python before upstream commands or confirmation" {
  setup_upstream
  source "$KIT_ROOT/modules/design/module.sh"
  hide_runtime
  MISSING_RUNTIME=python3
  run -127 module_check
  [[ $status == 127 && $output == *'python3 is required'* ]]
  run -127 install_apple_hig
  [[ $status == 127 && $output == *'sudo apt install python3'* && $output != *'Official command:'* && $output != *'unexpected confirmation'* ]]
  [[ ! -e $HOME/.claude/skills/apple-hig && ! -e $HOME/commands ]]
}
@test "Impeccable and binary helpers preflight runtimes before confirmation" {
  setup_upstream
  source "$KIT_ROOT/modules/design/module.sh"
  hide_runtime
  MISSING_RUNTIME=npx
  run -127 install_impeccable
  [[ $status == 127 && $output == *'npx is required'* && $output != *'unexpected confirmation'* ]]
  MISSING_RUNTIME=sh
  run -127 upstream_binary test-binary https://example.com https://example.com/install.sh sh
  [[ $status == 127 && $output == *'sh is required'* && $output != *'Official command:'* ]]
}
@test "binary displays exact download and execution commands with supplied environment pin" {
  setup_upstream
  UPSTREAM_YES=1
  cat >"$HOME/mock/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$4" >"$HOME/download-path"
printf '%s\n' 'printf "%s" "$DEMO_VERSION" >"$HOME/actual-version"' >"$4"
MOCK
  chmod +x "$HOME/mock/curl"
  run upstream_binary test-binary https://example.com https://example.com/install.sh bash --env DEMO_VERSION=v9.8.7 -- --version v9.8.7
  [[ $status == 0 && $(cat "$HOME/actual-version") == v9.8.7 ]]
  local installer
  installer=$(cat "$HOME/download-path")
  [[ $output == *"Official command: curl -fsSL https://example.com/install.sh -o $installer"* ]]
  [[ $output == *"Official command: env DEMO_VERSION=v9.8.7 bash $installer --version v9.8.7"* ]]
  [[ $output != *' | '* && ! -e $installer ]]
}
@test "Windows list failures and empty distributions are treated as Ubuntu missing" {
  command -v pwsh >/dev/null || skip 'pwsh unavailable'
  run pwsh -NoProfile -Command '
    . ./install.ps1 -DryRun > $null
    if (Test-UbuntuListed -ExitCode 1 -Distros @("no distributions")) { throw "Failed list accepted" }
    if (Test-UbuntuListed -ExitCode 0 -Distros @()) { throw "Empty list accepted" }
    if (-not (Test-UbuntuListed -ExitCode 0 -Distros @("Ubuntu`0"))) { throw "Ubuntu missing" }
  '
  [[ $status == 0 ]]
}
@test "Windows dry-run installs Ubuntu when WSL exists without a distribution" {
  command -v pwsh >/dev/null || skip 'pwsh unavailable'
  run pwsh -NoProfile -File "$KIT_ROOT/install.ps1" -DryRun -SimulateMissingUbuntu
  [[ $status == 0 && $output == *"& wsl.exe '--install' '-d' 'Ubuntu'"* && $output == *'Register agent-kit RunOnce'* ]]
  [[ $output != *"'bash' '-lc'"* ]]
}
@test "Windows initialized rerun skips interactive shell but first-run fallback opens one" {
  command -v pwsh >/dev/null || skip 'pwsh unavailable'
  run pwsh -NoProfile -File "$KIT_ROOT/install.ps1" -DryRun -Resume
  [[ $status == 0 && $output == *'Resuming agent-kit setup'* && $output == *"'-d' 'Ubuntu' '--' 'true'"* ]]
  [[ $output != *'type exit'* && $output == *"'bash' '-lc'"* ]]
  run pwsh -NoProfile -File "$KIT_ROOT/install.ps1" -DryRun -SimulateUninitializedUbuntu
  [[ $status == 0 && $output == *'type exit'* ]]
}


@test "failed preflight records no new pending module and permits base uninstall" {
  setup_upstream
  mock_claude
  hide_runtime
  export MISSING_RUNTIME=npx
  export -f command
  run -127 "$KIT_ROOT/bin/agent-kit" install --modules writing --yes
  [[ $output == *'Failed preflight for module: writing'* && $output == *'npx is required'* ]]
  jq -e '(.modules|index("writing")) == null and ((.pending_modules // [])|index("writing")) == null' "$KIT_STATE"
  [[ ! -e $HOME/commands ]]
  run "$KIT_ROOT/bin/agent-kit" uninstall base
  [[ $status == 0 && ! -f $KIT_STATE ]]
}
@test "failed preflight preserves recovery intent from an earlier partial install" {
  setup_upstream
  mock_claude
  state_edit '.pending_modules=["writing"]'
  hide_runtime
  export MISSING_RUNTIME=npx
  export -f command
  run -127 "$KIT_ROOT/bin/agent-kit" install --modules writing --yes
  jq -e '.pending_modules == ["writing"]' "$KIT_STATE"
}
@test "a partial Skills CLI directory is retried and then recorded complete" {
  setup_upstream
  UPSTREAM_YES=1
  cat >"$HOME/mock/npx" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/commands"
mkdir -p "$HOME/.claude/skills/humanizer"
if [[ ${MOCK_PARTIAL:-1} == 1 ]]; then exit 7; fi
printf 'complete\n' >"$HOME/.claude/skills/humanizer/SKILL.md"
MOCK
  chmod +x "$HOME/mock/npx"
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 7 ]]
  ! upstream_owned humanizer
  jq -e '.upstream_attempts | any(.id == "humanizer")' "$KIT_STATE"
  export MOCK_PARTIAL=0
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 0 && $output != *'Preserving existing skill'* ]]
  [[ $(wc -l <"$HOME/commands") == 2 ]]
  upstream_owned humanizer
  jq -e '.upstream_attempts == []' "$KIT_STATE"
}
@test "retry accepts the shared skill symlink created by the Skills CLI" {
  setup_upstream
  UPSTREAM_YES=1
  cat >"$HOME/mock/npx" <<'MOCK'
#!/usr/bin/env bash
mkdir -p "$HOME/.agents/skills/humanizer" "$HOME/.claude/skills"
ln -sfn ../../.agents/skills/humanizer "$HOME/.claude/skills/humanizer"
if [[ ${MOCK_PARTIAL:-1} == 1 ]]; then exit 7; fi
printf 'complete\n' >"$HOME/.agents/skills/humanizer/SKILL.md"
MOCK
  chmod +x "$HOME/mock/npx"
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 7 ]]
  export MOCK_PARTIAL=0
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 0 && $(cat "$HOME/.claude/skills/humanizer/SKILL.md") == complete ]]
  upstream_owned humanizer
}
@test "uninstall removes partial skill attempts without claiming completion" {
  setup_upstream
  UPSTREAM_YES=1
  export MOCK_EXIT=7
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 7 ]]
  ! upstream_owned humanizer
  export MOCK_EXIT=0
  run upstream_uninstall
  [[ $status == 0 && $(tail -1 "$HOME/commands") == '--offline --yes skills@1.7.2 remove humanizer --global --agent claude-code --yes' ]]
  jq -e '.upstream_attempts == []' "$KIT_STATE"
}
@test "Windows bootstrap passes a single quote-free encoded command to WSL" {
  command -v pwsh >/dev/null || skip 'pwsh unavailable'
  run pwsh -NoProfile -Command '
    . ./install.ps1 -DryRun > $null
    if ($WslBootstrapCommand.Contains([char]34) -or $WslBootstrapCommand.Contains("`n") -or $WslBootstrapCommand.Contains("`r")) { throw "Unsafe native argument" }
    $Decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedLinuxCommand))
    if ($Decoded -cne $LinuxCommand) { throw "Payload changed" }
    if (-not $WslBootstrapCommand.Contains($EncodedLinuxCommand)) { throw "Missing encoded payload" }
    if (-not $Decoded.Contains($BootstrapUrl) -or -not $Decoded.Contains($KitRef)) { throw "Pin missing" }
    $Printed = Show-WslCommand -WslArguments @("-d", "Ubuntu", "--", "bash", "-lc", $WslBootstrapCommand)
    if (-not $Printed.Contains($WslBootstrapCommand)) { throw "Dry-run differs from execution" }
  '
  [[ $status == 0 ]]
}


@test "retry refuses a skill directory replaced by an external symlink" {
  setup_upstream
  UPSTREAM_YES=1
  export MOCK_EXIT=7
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status == 7 ]]
  mkdir -p "$HOME/external" "$HOME/.claude"
  ln -s "$HOME/external" "$HOME/.claude/skills"
  export MOCK_EXIT=0
  run upstream_skill blader/humanizer deadbeef humanizer
  [[ $status != 0 && $output == *'Preserving external skill directory'* ]]
  [[ $(wc -l <"$HOME/commands") == 1 ]]
  ! upstream_owned humanizer
  jq -e '.upstream_attempts | any(.id == "humanizer")' "$KIT_STATE"
}
