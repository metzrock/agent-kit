#!/usr/bin/env bats
load helper
setup_repo() {
  repo=$BATS_TEST_TMPDIR/repo
  mkdir -p "$repo"
  cd "$repo"
  git init -q
  git config user.name 'Test Contributor'
  git config user.email 'noreply@example.com'
}
@test "whole tree scans untracked files and honors external rules" {
  setup_repo
  mkdir -p "$HOME/.config/agent-kit"
  printf 'forbidden-marker\n' >"$HOME/.config/agent-kit/denylist"
  echo forbidden-marker >sample.txt
  run "$KIT_ROOT/tools/leak-check" --all
  [[ $status == 1 && $output == *'sample.txt:1:forbidden-marker'* ]]
}
@test "staged scanner reads the index rather than modified worktree" {
  setup_repo
  printf '/%s/%s/private\n' home sample >sample.txt
  git add sample.txt
  echo safe >sample.txt
  run "$KIT_ROOT/tools/leak-check" --staged
  [[ $status == 1 && $output == *'sample.txt:1:'* ]]
}
@test "commit range catches removed leaks" {
  setup_repo
  echo safe >sample.txt
  git add sample.txt; git commit -qm initial
  old=$(git rev-parse HEAD)
  printf '%s.%s.%s.%s\n' 192 168 1 2 >sample.txt
  git add sample.txt; git commit -qm changed
  echo safe >sample.txt
  git add sample.txt; git commit -qm cleaned
  run "$KIT_ROOT/tools/leak-check" --range "$old" HEAD
  [[ $status == 1 && $output == *'sample.txt:1:'* ]]
}
@test "email exceptions pass while other addresses fail" {
  setup_repo
  printf 'noreply@sample.org\nuser@example.com\n' >sample.txt
  run "$KIT_ROOT/tools/leak-check" --all
  [[ $status == 0 ]]
  printf '%s@%s.%s\n' user sample org >>sample.txt
  run "$KIT_ROOT/tools/leak-check" --all
  [[ $status == 1 ]]
}

@test "secret scanner checks revisions before a secret is overwritten" {
  setup_repo
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/gitleaks" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if grep -Rq 'secret-fixture-marker' "$2"; then exit 1; fi
MOCK
  chmod +x "$HOME/mock/gitleaks"
  echo safe >sample.txt
  git add sample.txt; git commit -qm initial
  old=$(git rev-parse HEAD)
  echo secret-fixture-marker >sample.txt
  git add sample.txt; git commit -qm changed
  echo safe >sample.txt
  git add sample.txt; git commit -qm cleaned
  run env PATH="$HOME/mock:$PATH" "$KIT_ROOT/tools/leak-check" --range "$old" HEAD
  [[ $status == 1 ]]
}

@test "commit-msg hook blocks personal strings and external denylist hits" {
  setup_repo
  mkdir -p tools "$HOME/.config/agent-kit"
  cp "$KIT_ROOT/tools/leak-check" tools/leak-check
  printf '/%s/%s/private\n' home sample >message.txt
  run "$KIT_ROOT/hooks/commit-msg" "$repo/message.txt"
  [[ $status == 1 && $output == *'commit-message:1:'* ]]
  echo message-denied >"$HOME/.config/agent-kit/denylist"
  echo MESSAGE-DENIED >message.txt
  run "$KIT_ROOT/hooks/commit-msg" "$repo/message.txt"
  [[ $status == 1 && $output == *'commit-message:1:MESSAGE-DENIED'* ]]
  echo safe >message.txt
  run "$KIT_ROOT/hooks/commit-msg" "$repo/message.txt"
  [[ $status == 0 ]]
}
@test "range scan catches a leak present only in a commit message" {
  setup_repo
  echo safe >sample.txt
  git add sample.txt; git commit -qm initial
  old=$(git rev-parse HEAD)
  message=$(printf '/%s/%s/private' home sample)
  git commit --allow-empty -qm "$message"
  run "$KIT_ROOT/tools/leak-check" --range "$old" HEAD
  [[ $status == 1 && $output == *'commit-message:1:'* ]]
}
@test "CGNAT boundary addresses are blocked in staged files" {
  setup_repo
  for second in 64 127; do
    printf '%s.%s.%s.%s\n' 100 "$second" 1 2 >sample.txt
    git add sample.txt
    run "$KIT_ROOT/tools/leak-check" --staged
    [[ $status == 1 && $output == *'sample.txt:1:'* ]]
  done
  for second in 63 128; do
    printf '%s.%s.%s.%s\n' 100 "$second" 1 2 >sample.txt
    git add sample.txt
    run "$KIT_ROOT/tools/leak-check" --staged
    [[ $status == 0 ]]
  done
}
@test "batched scanning reports exact lines once and handles no final newline" {
  setup_repo
  mkdir -p "$HOME/.config/agent-kit"
  echo forbidden-marker >"$HOME/.config/agent-kit/denylist"
  awk 'BEGIN { for (i=1;i<=2000;i++) print "safe" }' >sample.txt
  printf 'forbidden-marker %s@%s.%s' user sample org >>sample.txt
  run "$KIT_ROOT/tools/leak-check" --all
  [[ $status == 1 && $output == *'sample.txt:2001:'* ]]
  [[ $(printf '%s\n' "$output" | grep -c 'sample.txt:2001:') == 1 ]]
}
@test "range scan materializes reused blobs once and checks sensitive renames" {
  setup_repo
  mkdir -p "$HOME/mock"
  cat >"$HOME/mock/gitleaks" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
find "$2/blobs" -type f | wc -l >"$HOME/blob-count"
MOCK
  chmod +x "$HOME/mock/gitleaks"
  echo safe >sample.txt
  git add sample.txt; git commit -qm initial
  old=$(git rev-parse HEAD)
  git mv sample.txt renamed.txt; git commit -qm rename
  git mv renamed.txt again.txt; git commit -qm rename-again
  run env PATH="$HOME/mock:$PATH" "$KIT_ROOT/tools/leak-check" --range "$old" HEAD
  [[ $status == 0 && $(cat "$HOME/blob-count") -eq 1 ]]
  git mv again.txt .env
  git commit -qam sensitive-rename
  run "$KIT_ROOT/tools/leak-check" --range "$old" HEAD
  [[ $status == 1 && $output == *'forbidden sensitive filename'* ]]
}
@test "malformed external patterns fail without exposing their contents" {
  setup_repo
  mkdir -p "$HOME/.config/agent-kit"
  echo '[invalid-private-pattern' >"$HOME/.config/agent-kit/denylist"
  run "$KIT_ROOT/tools/leak-check" --all
  [[ $status == 2 && $output == 'Invalid external denylist pattern' ]]
}
@test "a personal author email is blocked before commit, on push and in a full scan" {
  setup_repo
  echo clean >sample.txt; git add sample.txt
  git config user.email 'someone@example.com'
  run "$KIT_ROOT/tools/leak-check" --staged
  [ "$status" -eq 1 ] && [[ $output == *'not a noreply address: someone@example.com'* ]]
  git commit -qm initial --no-verify
  run "$KIT_ROOT/tools/leak-check" --range 0000000000000000000000000000000000000000 HEAD
  [ "$status" -eq 1 ] && [[ $output == *'author email is not a noreply address'* ]]
  run "$KIT_ROOT/tools/leak-check" --all
  [ "$status" -eq 1 ] && [[ $output == *'committer email is not a noreply address'* ]]
}
@test "a GitHub noreply author passes" {
  setup_repo
  git config user.email '123+someone@users.noreply.github.com'
  echo clean >sample.txt; git add sample.txt
  run "$KIT_ROOT/tools/leak-check" --staged
  [ "$status" -eq 0 ]
  git commit -qm initial
  run "$KIT_ROOT/tools/leak-check" --all
  [ "$status" -eq 0 ]
}
