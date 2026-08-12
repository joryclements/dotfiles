# dotfiles

Personal DevPod dotfiles. DevPod clones this repo to `$HOME/dotfiles` inside every
workspace and runs `install.sh` during container setup.

## What it does

Installs a chosen set of Claude Code plugins into every DevPod.

Plugin state (`~/.claude/settings.json`, `~/.claude/plugins/`) lives on the
per-workspace PVC. It survives `bin/dpod stop` / `ssh` on the same pod, but a new
workspace starts from the prebuild image baseline — which knows only the
`betterup-engineering` marketplace. Re-installing on every create is what makes a
personal plugin durable across pods.

## Adding a plugin

Add a line to `PLUGINS` in `install.sh`:

```bash
PLUGINS=(
  "ayghri/i-have-adhd i-have-adhd@i-have-adhd"
  "<marketplace-source> <plugin>@<marketplace>"
)
```

`<marketplace-source>` is whatever `claude plugin marketplace add` accepts —
`owner/repo`, a URL, or a path. `<plugin>@<marketplace>` comes from the source
repo's `.claude-plugin/marketplace.json` (`plugins[].name` @ top-level `name`).

## Enabling it

Per machine you launch pods from — this is a DevPod *context* option, so it is not
synced between your laptop and a pod:

```bash
bin/dpod options set DOTFILES_URL=https://github.com/joryclements/dotfiles
bin/dpod options list   # confirm
```

Takes effect on the next `bin/dpod create` / `rebuild`. Verify in a fresh pod with
`claude plugin list`.

## Design notes

- **Never symlink `.claude/settings.json` into `$HOME`.** The BetterUp prebuild
  image baseline carries the dpod statusline, the clipboard `UserPromptSubmit`
  hook, and the `betterup-engineering` marketplace. `claude plugin install` merges
  into that file; a symlink would clobber all three, and
  `Devpods::ClipboardHookInstaller` would then write back into this repo.
- **Public on purpose.** DevPod's agent clones dotfiles early in container setup,
  possibly before in-pod GitHub auth is configured, so a private clone can fail on
  credentials. Nothing here is sensitive. Keep it that way.
- **Everything is non-fatal** (`|| true`, `set -uo pipefail` without `-e`). A
  dotfiles failure must not block a pod from starting.

## Supply chain

Each plugin listed here injects instruction content into every Claude Code session
in every pod, pulled from a repo you may not control (the monolith sets
`FORCE_AUTOUPDATE_PLUGINS=1`). For anything you want pinned rather than
auto-updating, fork it and point the marketplace source at the fork.
