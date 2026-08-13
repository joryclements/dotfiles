#!/usr/bin/env bash
#
# Dotfiles install script. DevPod runs this on every `bin/dpod create` /
# `rebuild`, after cloning this repo to $HOME/dotfiles inside the container.
#
# Everything here re-applies per-pod state that lives on the workspace PVC and
# therefore does NOT carry to a new pod on its own.
#
# Deliberately non-fatal throughout: a dotfiles failure must not stop a pod
# from coming up.
set -uo pipefail

# ---------------------------------------------------------------------------
# 1. herdr-mirror remote_bin shim
# ---------------------------------------------------------------------------
# betterup/herdr-devpods' bin/dpod-mirror-sync hardcodes
#   remote_bin = "~/.local/share/mise/shims/herdr"
# for every pod it writes into hosts.toml, on the assumption that DevPod
# provisioning installs herdr through mise. The monolith image does not: its
# Dockerfile curls a SHA-pinned binary to /usr/local/bin/herdr and no mise
# config manages herdr. So the generated path does not exist and herdr-mirror
# cannot reach the pod's herdr API — even though dpod-mirror-sync's own probe
# (which uses bare `herdr` from PATH) reports the pod as mirrorable.
#
# This symlink makes the generated remote_bin resolve. Remove it if upstream
# starts deriving remote_bin instead of hardcoding it.
if [ -x /usr/local/bin/herdr ]; then
  mkdir -p "$HOME/.local/share/mise/shims"
  ln -sfn /usr/local/bin/herdr "$HOME/.local/share/mise/shims/herdr"
  echo "dotfiles: linked mise shim -> /usr/local/bin/herdr (herdr-mirror remote_bin)"
else
  echo "dotfiles: no /usr/local/bin/herdr, skipping mirror shim"
fi

# ---------------------------------------------------------------------------
# 2. Claude Code plugins
# ---------------------------------------------------------------------------
# One entry per plugin: "<marketplace-source> <plugin>@<marketplace>"
# marketplace-source is anything `claude plugin marketplace add` accepts
# (owner/repo, URL, or path).
PLUGINS=(
  "ayghri/i-have-adhd i-have-adhd@i-have-adhd"
)

if command -v claude >/dev/null 2>&1; then
  for entry in "${PLUGINS[@]}"; do
    read -r source plugin <<<"$entry"

    echo "dotfiles: adding marketplace $source"
    claude plugin marketplace add "$source" || true

    echo "dotfiles: installing plugin $plugin"
    claude plugin install "$plugin" --scope user || true
  done
else
  echo "dotfiles: claude CLI not on PATH, skipping plugin install"
fi

echo "dotfiles: done"
