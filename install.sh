#!/usr/bin/env bash
#
# Dotfiles install script. DevPod runs this on every `bin/dpod create` /
# `rebuild`, after cloning this repo to $HOME/dotfiles inside the container.
#
# Purpose: make a chosen set of Claude Code plugins present in every DevPod.
# Plugin state lives in ~/.claude/ on the per-workspace PVC, so it does not
# carry to a new pod on its own — re-installing here is what makes it durable.
#
# Deliberately non-fatal throughout: a dotfiles failure must not stop a pod
# from coming up.
set -uo pipefail

# One entry per plugin: "<marketplace-source> <plugin>@<marketplace>"
# marketplace-source is anything `claude plugin marketplace add` accepts
# (owner/repo, URL, or path).
PLUGINS=(
  "ayghri/i-have-adhd i-have-adhd@i-have-adhd"
)

if ! command -v claude >/dev/null 2>&1; then
  echo "dotfiles: claude CLI not on PATH, skipping plugin install"
  exit 0
fi

for entry in "${PLUGINS[@]}"; do
  read -r source plugin <<<"$entry"

  echo "dotfiles: adding marketplace $source"
  claude plugin marketplace add "$source" || true

  echo "dotfiles: installing plugin $plugin"
  claude plugin install "$plugin" --scope user || true
done

echo "dotfiles: done"
