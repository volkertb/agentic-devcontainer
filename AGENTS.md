<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md

`CLAUDE.md` is a symlink to this file. Edit `AGENTS.md`; never replace the symlink with a file.

Container environment (portable, travels with `.devcontainer/`): @.devcontainer/AGENTS.md

## What this project is

The dev container itself. There is no application code: the product is `.devcontainer/` plus
`README.md`. People copy `.devcontainer/` into other projects, so it must stay self-contained —
anything an agent needs to know *inside* the container goes in `.devcontainer/AGENTS.md` or
`.devcontainer/agent_docs/`, not here.

`README.md` is the human-facing documentation and the source of truth for how things work.
Read the relevant section before changing anything; update it in the same commit when
behaviour changes. Any command shown there must have been run as written.

## Layout

- `.devcontainer/` — `devcontainer.json` (+ `devcontainer-lock.json`), `Dockerfile`, `codex-config.toml`, `specstory-config.toml`, `codex-wrapper.sh`,
  `bwrap-shim.sh`, `seccomp.json` (+ `make-seccomp.sh`), `patch-chat-template.sh`, `AGENTS.md`,
  `agent_docs/`.
- `agent_docs/` — this-repo-only detail: `decisions.md`, `verifying-changes.md`.
- `.specstory/history/` — saved sessions. `.claude-backup/` — raw Claude transcripts, git-ignored.

## Conventions

- Every file starts with the three SPDX lines; copy the comment style from a neighbouring file.
  Exceptions: files with no comment syntax (`seccomp.json`, generated) and `LICENSE.md`.
- Commit subjects: `feat:` / `docs:` / `chore:` + imperative summary; body says why.
  Commit when asked; **never push** — the user pushes.
- Scripts are bash with `set -euo pipefail` and must pass `shellcheck`. Run them for real
  before claiming they work; see `agent_docs/verifying-changes.md`.
- When a choice isn't explained by the code, add a dated entry to `agent_docs/decisions.md`.
- `.specstory/` is committed and synced by the user only, between sessions — never stage it,
  even when asked to "commit everything". Agents may audit it for secrets when asked; the
  transcript of a running session is still being written, so an in-session commit can never
  be a clean snapshot.
