#!/usr/bin/env bash
#
# Dotfiles install script. DevPod runs this on every `bin/dpod create` /
# `rebuild`, after cloning this repo to $HOME/dotfiles inside the container.
#
# Purpose: make a chosen set of Claude Code plugins present AND active in every
# DevPod. Plugin state lives in ~/.claude/ on the per-workspace PVC, so it does
# not carry to a new pod on its own — re-installing here is what makes it
# durable.
#
# Installing a plugin is not the same as switching it on. A plugin whose
# behaviour is gated behind a flag file (i-have-adhd's always-on SessionStart
# hook) stays dormant until that file exists, so ALWAYS_ON_FLAGS below is what
# turns it on.
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

# Flag files created under the Claude config dir. A plugin hook that gates on
# its own flag file reads these; creating one is the opt-in.
#   i-have-adhd: .i-have-adhd-always makes the SessionStart hook inject the
#   ruleset from message one of every session, instead of waiting for the
#   /i-have-adhd skill to be invoked by hand.
ALWAYS_ON_FLAGS=(
  ".i-have-adhd-always"
)

# Private companion repo holding personal skills whose content can't be public.
# See the skills block below for why the split exists.
PRIVATE_SKILLS_REPO="joryclements/claude-skills"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

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

# ccstatusline widget config — the statusLine command merged into settings.json
# below reads this, so copying it keeps pods rendering the same line as local.
# Clobber on purpose: this repo is the source of truth for pod appearance.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/ccstatusline/settings.json" ]; then
  mkdir -p "$HOME/.config/ccstatusline"
  cp "$SCRIPT_DIR/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json" || true
  echo "dotfiles: installed ccstatusline config"
fi

# herdr config — the image seeds none, so without this every pod defaults to
# mouse_capture = true and drag-select stops copying out of nested herdr panes.
# Seed only when absent, unlike the clobbering copy above: a fresh pod has no
# config, while a laptop running this has a hand-tuned one worth keeping.
if [ -f "$SCRIPT_DIR/herdr/config.toml" ] && [ ! -e "$HOME/.config/herdr/config.toml" ]; then
  mkdir -p "$HOME/.config/herdr"
  cp "$SCRIPT_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml" || true
  echo "dotfiles: installed herdr config"
fi

# herdr-plugins helper — a small CLI to see and update the GitHub herdr plugins
# you have installed (herdr v1 has no `plugin update`; it wraps the standard
# `herdr plugin install --ref`), and to reload the mirror binary into running
# streamers after an update. Clobber-copy onto PATH: this repo is the source of
# truth for it. It only ever acts on herdr plugins you installed yourself, so on
# a pod that has none it simply reports nothing.
if [ -f "$SCRIPT_DIR/bin/herdr-plugins" ]; then
  mkdir -p "$HOME/.local/bin"
  cp "$SCRIPT_DIR/bin/herdr-plugins" "$HOME/.local/bin/herdr-plugins" || true
  chmod +x "$HOME/.local/bin/herdr-plugins" || true
  echo "dotfiles: installed herdr-plugins helper"
fi

# Personal skills from the private companion repo. They carry real content -
# verbatim quotes, account names, internal schema - so they cannot live in this
# repo, which is public by necessity (DevPod's agent clones it before in-pod
# GitHub auth is guaranteed). This script runs later, after on-create has run
# `gh auth setup-git`, so by here `gh` is usable and the private clone works.
# Non-fatal like everything else: no auth, no network, or no access just means a
# pod without these skills, never a pod that fails to start.
if command -v gh >/dev/null 2>&1; then
  SKILLS_TMP="$(mktemp -d)"
  if gh repo clone "$PRIVATE_SKILLS_REPO" "$SKILLS_TMP/repo" -- --depth 1 --quiet 2>/dev/null; then
    if [ -d "$SKILLS_TMP/repo/skills" ]; then
      mkdir -p "$CLAUDE_DIR/skills"
      # Sync per skill, never the whole skills dir: it also holds symlinks to
      # locally-installed skills (git-ai, herdr) that this repo knows nothing
      # about and must not disturb. --delete is scoped to one skill dir so a
      # file dropped upstream disappears here too. --checksum because the
      # default size+mtime quick check silently skips a same-size edit, which
      # is a realistic way to revise prose; these files are tiny so hashing
      # them costs nothing. cp is the fallback when rsync is absent.
      for skill in "$SKILLS_TMP/repo/skills"/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        dest="$CLAUDE_DIR/skills/$name"
        mkdir -p "$dest"
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --checksum --delete "$skill" "$dest/" || true
        else
          cp -R "$skill." "$dest/" || true
        fi
        echo "dotfiles: installed skill $name"
      done
    fi
  else
    echo "dotfiles: could not clone $PRIVATE_SKILLS_REPO (no auth or no access), skipping personal skills"
  fi
  rm -r "$SKILLS_TMP" 2>/dev/null || true
fi

mkdir -p "$CLAUDE_DIR"
for flag in "${ALWAYS_ON_FLAGS[@]}"; do
  echo "dotfiles: enabling always-on flag $flag"
  touch "$CLAUDE_DIR/$flag" || true
done

# `claude plugin install` is expected to record enabledPlugins itself. Assert it
# rather than trust it: an install that half-succeeds leaves a plugin present but
# switched off, which looks identical to a working pod until a session starts
# without the ruleset. Merge in place — never rewrite settings.json wholesale,
# because the prebuild baseline's statusline, clipboard hook, and
# betterup-engineering marketplace live in the same file (see README).
python3 - "$CLAUDE_DIR/settings.json" "${PLUGINS[@]}" <<'PY' || true
import json
import os
import sys
import tempfile

path, entries = sys.argv[1], sys.argv[2:]

try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (OSError, ValueError):
    data = {}

enabled = data.get("enabledPlugins")
if not isinstance(enabled, dict):
    enabled = {}

changed = False
for entry in entries:
    plugin = entry.split()[1]
    if enabled.get(plugin) is not True:
        enabled[plugin] = True
        changed = True
        print(f"dotfiles: enabling {plugin} in settings.json")

# ccstatusline (github.com/sirmalloc/ccstatusline) replaces the prebuild
# baseline's dpod statusline. npx caches the package after the first render.
statusline = {"type": "command", "command": "npx -y ccstatusline@latest"}
if data.get("statusLine") != statusline:
    data["statusLine"] = statusline
    changed = True
    print("dotfiles: setting statusLine to ccstatusline in settings.json")

if not changed:
    sys.exit(0)

data["enabledPlugins"] = enabled

# Atomic write: never leave settings.json truncated if interrupted, since
# Claude Code may read it before this script re-runs.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".tmp")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
except BaseException:
    os.unlink(tmp)
    raise
PY

echo "dotfiles: done"
