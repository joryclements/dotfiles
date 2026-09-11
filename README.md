# dotfiles

Personal DevPod dotfiles. DevPod clones this repo to `$HOME/dotfiles` inside every
workspace and runs `install.sh` during container setup.

## What it does

Installs a chosen set of Claude Code plugins into every DevPod, and switches on
the ones whose behaviour is gated behind a flag file.

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

## Always-on flags

Installing a plugin does not necessarily switch it on. Some plugins ship a
`SessionStart` hook that fires only when a flag file exists, so the plugin sits
inert until you create one. `ALWAYS_ON_FLAGS` in `install.sh` is that opt-in:

```bash
ALWAYS_ON_FLAGS=(
  ".i-have-adhd-always"
)
```

Each entry is `touch`ed under `$CLAUDE_CONFIG_DIR` (default `~/.claude`).
`.i-have-adhd-always` makes i-have-adhd's hook inject its ruleset from message
one of every session, rather than waiting for `/i-have-adhd` to be invoked by
hand.

To go back to on-demand for a plugin, drop its entry here and delete the file in
any pod that already has it.

## Enabling it

Per machine you launch pods from — this is a DevPod *context* option, so it is not
synced between your laptop and a pod:

```bash
bin/dpod options set DOTFILES_URL=https://github.com/joryclements/dotfiles
bin/dpod options list   # confirm
```

Takes effect on the next `bin/dpod create` / `rebuild`. Verify in a fresh pod with
`claude plugin list`.

## herdr-plugins helper

`bin/herdr-plugins` is installed onto `PATH` (`~/.local/bin`). It lists the GitHub
herdr plugins you have installed and tells you which are behind, then updates them
on request — herdr v1 has no `plugin update`, so it wraps the standard
`herdr plugin install --ref`:

```bash
herdr-plugins                   # status: installed vs latest, per plugin
herdr-plugins update mirror     # or `all`; reinstalls at the newest release tag
herdr-plugins restart-mirrors   # reload the mirror binary into running streamers
```

"Latest" is the newest release tag, or the default-branch tip for repos with no
releases. `update` restarts the mirror streamers for you when the `mirror` plugin
changes. It only touches herdr plugins you installed yourself, never pod images or
team tooling, so on a pod with none it reports nothing.

## Design notes

- **Never symlink `.claude/settings.json` into `$HOME`.** The BetterUp prebuild
  image baseline carries the dpod statusline, the clipboard `UserPromptSubmit`
  hook, and the `betterup-engineering` marketplace. `claude plugin install` merges
  into that file; a symlink would clobber all three, and
  `Devpods::ClipboardHookInstaller` would then write back into this repo.
- **Public on purpose.** DevPod's agent clones dotfiles early in container setup,
  possibly before in-pod GitHub auth is configured, so a private clone can fail on
  credentials. Nothing here is sensitive. Keep it that way.
- **`enabledPlugins` is asserted, not assumed.** `claude plugin install` is
  expected to record it, but a half-succeeded install leaves a plugin present
  and switched off — indistinguishable from a healthy pod until a session starts
  without the ruleset. `install.sh` merges the key in itself, atomically and
  idempotently.
- **Everything is non-fatal** (`|| true`, `set -uo pipefail` without `-e`). A
  dotfiles failure must not block a pod from starting.

## Supply chain

Each plugin listed here injects instruction content into every Claude Code session
in every pod, pulled from a repo you may not control (the monolith sets
`FORCE_AUTOUPDATE_PLUGINS=1`). For anything you want pinned rather than
auto-updating, fork it and point the marketplace source at the fork.
