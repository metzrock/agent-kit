#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'Review plans and code with Plannotator'; }
module_deps() { echo 'base'; }
module_check() { upstream_require curl bash claude; }
module_install() {
  upstream_binary plannotator https://github.com/backnotprop/plannotator https://raw.githubusercontent.com/backnotprop/plannotator/b76c6d48dab67d44a5600117a0eea39955995042/scripts/install.sh bash --version v0.28.20 --minimal || return
  upstream_plugin backnotprop/plannotator plannotator@plannotator v0.28.20 || return
}
module_uninstall() { upstream_uninstall; }
