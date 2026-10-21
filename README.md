# Claude Code offline installer

A mirror of the Claude Code native binaries, so Claude Code can be installed on
a machine with no internet access. Keep this repo **private**.

## Install (offline)

```sh
git clone <this repo>        # on any machine with access, then copy it over
cd claude-offline
./install.sh                 # or: ./install.sh 2.1.306 / ./install.sh stable
```

It picks the binary for your OS/arch (linux x64/arm64, glibc or musl; macOS
x64/arm64), checks its SHA-256 against the official manifest, installs it to
`~/.local/share/claude/versions/<version>` with a `~/.local/bin/claude` symlink
(the same layout as the official installer), and sets `DISABLE_AUTOUPDATER=1`
in `~/.claude/settings.json`.

The official installer's `claude install` step always contacts
downloads.claude.ai, so this script sets up the files itself instead.

Using Claude Code still needs network access to the Anthropic API (or your
Bedrock/Vertex endpoint). Only the install is offline.

## Update the mirror (online)

```sh
./mirror.sh                          # latest, all six platforms
./mirror.sh stable linux-x64         # one channel, chosen platforms
git add releases && git commit -m "Mirror Claude Code <version>" && git push
```

Binaries are ~280MB, over GitHub's 100MB per-file limit, so each is stored as
95MB parts and joined at install time. Every version adds about 1.7GB for all
six platforms; delete old `releases/<version>/` folders to keep the repo small.
