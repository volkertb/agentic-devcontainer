<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# Session continuity across rebuilds

Nothing under the container user's home is mounted. A rebuild or recreate discards:

| Path | Holds |
|---|---|
| `~/.claude/projects/<slug>/*.jsonl` | Claude Code transcripts (what `claude --resume` needs) |
| `~/.claude/projects/<slug>/memory/` | Claude Code's persistent memory for this project |
| `~/.claude/.credentials.json`, settings | Login — must log in again after a rebuild |
| `~/.codex/sessions/**/rollout-*.jsonl` | Codex transcripts |
| `~/.codex/*.sqlite`, `~/.codex/rules/` | Codex state, approved-command rules |

The workspace folder is a bind mount and survives.

## Before a rebuild — run this, last

```bash
specstory sync && cp -a ~/.claude/projects .claude-backup/
```

`specstory sync` writes every Claude Code and Codex session for this directory to
`.specstory/history/*.md` (local, no account). The copy keeps the raw transcripts and memory
so sessions can be resumed rather than only read. `.claude-backup/` must be git-ignored — it
can hold anything said in a session. Add it to `.gitignore` when copying this container into
another project.

## After a rebuild

```bash
cp -a .claude-backup/projects ~/.claude/ && claude --resume
```

Then log in to Claude Code again. Codex needs nothing: its config is baked into the image.

## Resuming cold (new container, no backup)

Read, in order: the project's `AGENTS.md`, its `README.md`, then the most recent files in
`.specstory/history/`. The git log is written to be read (`git log --format='%s%n%n%b'`).

## Why no volume mounts

Deliberate: `~/.codex/config.toml` is baked into the image, and a volume would shadow it after
the first mount, silently ignoring later config changes. Do not add `mounts` for `~/.claude` or
`~/.codex` without discussing it.
