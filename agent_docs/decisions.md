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

## 2026-09-20 — seccomp stays a file path in `runArgs` although JetBrains cannot apply it

JetBrains' dev-container support passes `seccomp=<file>` to the engine API verbatim instead of
reading the file like the `docker` CLI does (IJPL-67749, open since 2024). Inline JSON would fix
JetBrains but break the CLI, which treats anything but `unconfined` as a file name. Not worked
around: the config targets the spec and conforming implementations; README notes the bug.

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

## 2026-09-20 — bwrap shim instead of `systempaths=unconfined` (temporary)

Codex's sandbox failed at `--proc /proc` (Docker's masked `/proc`; openai/codex#44329). The
Docker-side fix unmasks `/proc/kcore`, `/proc/sys` etc. for the whole container to serve one
tool, and the container's isolation is the outer moat. Landlock-only mode (`use_legacy_landlock`)
panics under `workspace-write` in 0.155.1. The shim reproduces Codex's own `--no-proc` fallback
at the PATH level; it lives in `/usr/local/bin` rather than `~/.local/bin` because Codex skips a
`bwrap` found under the current directory, which `~` can be. It is a stopgap: remove it once
openai/codex#44329 is fixed, not a permanent part of the container.

## 2026-09-20 — SpecStory defaults shipped as a user-level config, not patched with sed

`specstory sync` warns "Cloud sync not available" on every run without a login. SpecStory
reads `~/.specstory/cli/config.toml` (user-level) and `./.specstory/cli/config.toml`
(project-level, wins per key) and writes a fully commented template to both on first run,
which is after the build — so there is nothing to `sed` at build time, and a
`postCreateCommand` would break the offline-creation rule. `~/.specstory` is not persisted,
so a hand-written user-level file `COPY`'d in the Dockerfile is the only thing that survives
a rebuild and covers every project that copies `.devcontainer/`. Verified that SpecStory
leaves a pre-existing file alone. Cloud sync and analytics off; version check kept, because
the notice is how one learns to bump `SPECSTORY_VERSION`. The same two keys are uncommented in
this repo's committed project-level file so they also hold when running on the host.

## Earlier (from git history)

- No root, no sudo, setuid stripped, `no-new-privileges`: the agent runs confined to `vscode`;
  root work is done via `docker exec -u root` from the host. (README → *Working as root*)
- Codex checksums pinned in the Dockerfile, not exposed as build args, so version and digest
  can't drift apart. (README → *Download verification*)
- Everything installed at build time; no `postCreateCommand`, so container creation is offline.
