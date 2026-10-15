#!/usr/bin/env bash
set -euo pipefail
module_describe() { echo 'GitHub, browser, token and Cloudflare helpers'; }
module_deps() { echo 'base'; }
module_check() { upstream_require npx node git claude sh; }
module_install() {
  upstream_skill kunchenguid/gh-axi 96e44e65506083f57d53e566df362c8cb2569034 gh-axi || return
  upstream_skill kunchenguid/chrome-devtools-axi b27878f07290a0d70bb5e8fdf5b9fe8f819de78a chrome-devtools-axi || return
  upstream_binary rtk https://github.com/rtk-ai/rtk https://raw.githubusercontent.com/rtk-ai/rtk/5eb0509690a6f0110bb9bdd453fcf75c480e0d05/install.sh sh --env RTK_VERSION=v1.0.1 || return
  upstream_plugin cloudflare/skills cloudflare@cloudflare || return
}
module_uninstall() { upstream_uninstall; }
