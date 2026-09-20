<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# Verifying changes to the container configuration

There are no tests; every change has a concrete check. Show the output, don't assert.
The live-server and Codex probes are in `.devcontainer/agent_docs/codex-llama-server.md`.

| Changed | Check |
|---|---|
| Any `*.sh` | `shellcheck <file>`, then run it for real, against `$LLAMA_SERVER_URL` if it talks to the server |
| `seccomp.json` | `jq -e '.defaultAction and (.syscalls\|length) > 30'`; only a container recreate proves the rest |
| `devcontainer.json` `runArgs` | Needs a recreate. Cannot verify from inside — say so and give the user the in-container check |
| `devcontainer.json` `features` / `devcontainer-lock.json` | `npx --yes @devcontainers/cli@latest upgrade --workspace-folder . --dry-run` prints the lock the CLI would write; diff it against the committed file. This is the one CLI command that works without Docker (`read-configuration` and the rest shell out to `docker` first) |
| `Dockerfile` | Needs a rebuild. Cannot verify from inside — say so. A wrapper/config copied by hand into the running container (e.g. `~/.local/bin/codex`) is a stand-in until then; say that too |
| `bwrap-shim.sh` | Copy to `~/.local/bin/bwrap` as a stand-in (also first on PATH), then the two `codex sandbox` probes in the probes doc and a `codex exec -s workspace-write` that touches a file |
| `codex-config.toml` / `codex-wrapper.sh` | `codex exec -s read-only "Reply with the single word OK"`, then inspect the newest rollout (probes doc) |
| README command snippets | Run them exactly as written |
| `.devcontainer/AGENTS.md`, `.devcontainer/agent_docs/` | Must make sense in a project that is *not* this one: no paths or facts specific to this repo |
