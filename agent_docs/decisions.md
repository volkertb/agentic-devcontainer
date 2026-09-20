<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# Decisions

Why things are the way they are. Newest first. Add an entry when you make a choice that the
code cannot explain by itself.

## 2026-09-20 — Agent context split: portable in `.devcontainer/`, repo-specific at root

`.devcontainer/AGENTS.md` + `.devcontainer/agent_docs/` describe life inside the container and
travel with the directory when it is copied into other projects; the root `AGENTS.md` imports
it and adds only what is true of this repo. `CLAUDE.md` is a symlink so Claude Code and Codex
read one file.

## 2026-09-20 — Session continuity via SpecStory + AGENTS.md, not volume mounts

Considered named volumes for `~/.claude` and `~/.codex`. Rejected: `~/.codex/config.toml` is
baked into the image, and a volume would shadow it after the first mount, silently ignoring
config changes on rebuild. Instead: `specstory sync` + a raw-transcript copy before rebuilds,
and durable context in the AGENTS files. See `.devcontainer/agent_docs/session-continuity.md`.

## 2026-09-20 — Custom seccomp profile rather than `seccomp=unconfined`

Codex's sandbox needs unprivileged user namespaces; Docker's default profile blocks them.
`unconfined` would drop the whole syscall filter. The shipped profile is upstream default +
six syscalls, regenerable by script so it can track upstream. `no-new-privileges` stays on.
Trade-off (kernel userns attack surface) is stated in README → *Security notes*.

## 2026-09-20 — Wrapper passes model/context to Codex instead of hard-coding

Codex cannot query a custom provider and `config.toml` cannot compute values. A PATH-shadowing
wrapper with `-c` overrides was the only way to keep the config in sync with the server; the
config values remain as fallbacks for when the server is down at launch.

## 2026-09-20 — Chat-template fix is a generator script, not a committed template

The template is model-specific and comes from the running server; committing one would go
stale and imply the container is Qwen-specific. The script's workflow is model-neutral; the
per-model patch table is the only model-specific part.

## 2026-09-20 — `model = "local"` kept although the server ignores it

Single-model llama-server ignores the `model` field. Kept as the fallback for when the wrapper
cannot reach the server at launch.

## Earlier (from git history)

- No root, no sudo, setuid stripped, `no-new-privileges`: the agent runs confined to `vscode`;
  root work is done via `docker exec -u root` from the host. (README → *Working as root*)
- Codex checksums pinned in the Dockerfile, not exposed as build args, so version and digest
  can't drift apart. (README → *Download verification*)
- Everything installed at build time; no `postCreateCommand`, so container creation is offline.
