<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# Working inside this dev container

Portable with `.devcontainer/`. Projects that copy the directory point their own `AGENTS.md`
at this file. `README.md` in the source project has the human-facing detail.

- You run as `vscode` with no route to root (no sudo, setuid stripped, `no-new-privileges`).
  Root work happens from the host: `docker exec -u root`. Don't try to escalate.
- The host is `host.docker.internal`, never `127.0.0.1`. llama-server is `$LLAMA_SERVER_URL`.
- `codex` on `PATH` is `~/.local/bin/codex`, a wrapper that reads the served model and context
  size from llama-server at launch. `/usr/local/bin/codex` is the raw binary.
- `~/.claude` and `~/.codex` are NOT persisted across a rebuild or recreate. Before either,
  run the routine in `agent_docs/session-continuity.md` (relative to this directory).
- `Dockerfile` changes need a rebuild; `runArgs` changes (seccomp, env-file) need a recreate.
  Neither can be verified from inside the container — say so and give the check to run after.
- Everything installs at build time; there is no network at container creation.

## Read when relevant

- `agent_docs/session-continuity.md` — what a rebuild discards; save/restore routine.
- `agent_docs/codex-llama-server.md` — how the Codex integration works, its failure modes,
  the warnings that are not errors, and the live-server probes.
