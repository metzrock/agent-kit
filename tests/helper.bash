setup() {
  export KIT_ROOT
  KIT_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CREW_IMPLEMENTER CREW_AGENT XDG_CACHE_HOME XDG_DATA_HOME
}
common() { source "$KIT_ROOT/lib/common.sh"; state_init; }
