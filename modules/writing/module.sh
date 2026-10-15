#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Writing, planning and attention skills'; }
module_deps() { echo 'base'; }
module_check() { upstream_require npx node git claude; }
module_install() {
  upstream_skill blader/humanizer 225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8 humanizer || return
  upstream_skill mattpocock/skills 49dd158d1076134a641b33efb035946536778336 grill-me || return
  upstream_skill mattpocock/skills 49dd158d1076134a641b33efb035946536778336 handoff || return
  upstream_plugin ayghri/i-have-adhd i-have-adhd@i-have-adhd || return
}
module_uninstall() { upstream_uninstall; }
