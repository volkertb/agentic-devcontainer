<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# Generic dev container

Debian-based dev container for agentic coding: non-root user, a broad CLI toolchain,
Claude Code, Codex CLI and SpecStory.

## Which agents, which models

- **Claude Code** works as-is with an Anthropic account; nothing here changes it.
- **Codex CLI** is preconfigured for *local* models served by a `llama-server` — or any
  server speaking the OpenAI *Responses* API — listening on **port 9931 on your host**.
  Choosing, tuning and starting that server is up to you; this container only consumes it.
  See *llama-server on the host* below for the one host-side detail that matters.
  To use Codex with OpenAI or another hosted provider instead, edit
  `.devcontainer/codex-config.toml` yourself; that setup is not covered here.
- **Other agents** are not included. Install them in the container, or add them to the
  Dockerfile if you want them to survive a rebuild.

None of this is mandatory. The container is just as usable with Claude Code alone, or
with whatever agent you bring, without a local model server.

## First run

```bash
cp .devcontainer/.env.example .devcontainer/.env   # required: runArgs passes --env-file
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

VS Code, JetBrains and Zed pick the config up automatically when you open the folder.
JetBrains currently cannot start it because of a bug on their side; see *Codex's Linux sandbox*.

Nothing under the container's home directory survives a rebuild, and that includes
`~/.gitconfig`, so `git commit` inside the container fails with *Author identity unknown* until
you tell it who you are. Set the identity on the repository instead of globally — `.git/` is
in the workspace bind mount and persists:

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
```

Without `--global` this lands in `.git/config`, so it is per-project, survives rebuilds, and
does not leak the identity into other repositories the container might see. The same goes for
any other git setting you want to keep (`commit.gpgsign`, `core.sshCommand`, …). Your host's
`~/.gitconfig` is not mounted on purpose: it may name signing keys, credential helpers and
paths that do not exist inside the container.

## How to use it in your own project

See instructions below. Everything lives in `.devcontainer/`; nothing in it refers to this repository.

```bash
cd /path/to/agentic-devcontainer  # If your current working directory is not the root of this project
cp -r .devcontainer /path/to/your-project/
cd /path/to/your-project
cp .devcontainer/.env.example .devcontainer/.env
printf '%s\n' '.devcontainer/.env' '.claude-backup/' 'chat-template-patched.jinja' >> .gitignore
echo '@.devcontainer/AGENTS.md' >> AGENTS.md       # ln -s AGENTS.md CLAUDE.md if you have neither
devcontainer up --workspace-folder .
```

Then, optionally: change `"name"` in `devcontainer.json` so the container is recognisable in
`docker ps`, and delete `.devcontainer/AGENTS.md` and `.devcontainer/agent_docs/` if you
don't use coding agents in it. The `.gitignore` lines cover, in order: your secrets, the raw
transcript backup, and the output of the chat-template script — see *SpecStory* and
*Model-specific considerations*.

## What's inside

| | |
|---|---|
| Base | `mcr.microsoft.com/devcontainers/base:trixie` (Debian 13), amd64 + arm64 |
| User | `vscode`, uid 1000, **no route to root**, uid realigned to your host user on Linux |
| Tools | gcc/g++/make/cmake, gdb, Python 3 + pipx + uv, Node LTS, git, jq, ripgrep, fd, bat, fzf, xxd, sqlite3, socat, tmux, shellcheck, archives, net utils |
| Agents | Claude Code, Codex CLI (`codex`) |
| Capture | SpecStory CLI (`specstory`) |

Everything is installed at build time — there is no `postCreateCommand`, so creating a
container from a built image is instant and needs no network.

## Codex and llama-server

`.devcontainer/codex-config.toml` is copied to `~/.codex/config.toml` during the build.
The one change from a host-side Codex setup: the endpoint is **`host.docker.internal`**,
not `127.0.0.1`, which inside a container means the container itself.

```toml
model_provider = "llamacpp"
model = "local"               # fallback only, see below
model_context_window = 32768  # fallback only, see below

[model_providers.llamacpp]
name = "llama.cpp"
base_url = "http://host.docker.internal:9931/v1"
wire_api = "responses"
```

Top-level keys must stay above the `[model_providers.*]` header or TOML folds them into
that table. No API key is needed — a keyless local endpoint is a first-class case for
Codex. If your server requires one, add `env_key = "MY_VAR"` and set `MY_VAR` in `.env`.

Verify the endpoint from inside the container before blaming Codex:

```bash
curl $LLAMA_SERVER_URL/v1/responses \
  -H "Content-Type: application/json" \
  -d '{"model":"local","input":"say hi","stream":false}'
```

A Responses-shaped object back means the integration surface is good; then just run `codex`.
For a one-off test against a different endpoint without editing the config,
`CODEX_OSS_BASE_URL=http://host.docker.internal:9931/v1` overrides Codex's built-in OSS provider.

### Codex's Linux sandbox

Codex runs commands inside a bubblewrap sandbox, which needs unprivileged user namespaces.
Docker's default seccomp profile blocks the syscalls involved (`unshare`, `mount`,
`pivot_root`, …), so out of the box Codex warns *"Codex's Linux sandbox uses bubblewrap and
needs access to create user namespaces"* and every command needs escalation.

The container therefore runs with `.devcontainer/seccomp.json`: Docker's default profile with
exactly those syscalls allowed unconditionally — nothing else is loosened.

That gets bubblewrap its namespaces; one more thing stands between it and Docker. Codex asks
bubblewrap for a fresh procfs (`--proc /proc`), and Docker masks parts of the container's
`/proc` (`/proc/kcore`, `/proc/sys`, …), which makes the kernel refuse a new procfs from an
unprivileged user namespace: *"bwrap: Can't mount proc on /proc: Operation not permitted"*,
surfacing in Codex as *"Sandbox hiccup, retrying"* and then *"Sandbox is broken in this
environment"*. Codex has a fallback for exactly this — rerun without `--proc` — but it
recognises the failure only by bubblewrap's pre-0.12 wording (`/newroot/proc`), and Debian 13
ships 0.12.0 ([openai/codex#44329](https://github.com/openai/codex/issues/44329)). Docker's
own remedy, `--security-opt systempaths=unconfined`, unmasks those paths for the whole
container, which is the wrong trade.

**Temporary workaround, until that issue is fixed upstream:** `.devcontainer/bwrap-shim.sh` is
installed as `/usr/local/bin/bwrap`, ahead of the real binary. It probes once, drops `--proc`
if the kernel refuses it, and `exec`s `/usr/bin/bwrap` with everything else untouched — the
same decision Codex's own fallback would make. The sandbox then runs with the container's
`/proc` bind-mounted instead of a fresh one. What that costs: sandboxed
commands see the container's process list (`ps` shows PIDs from outside), and with it the
command lines of other processes in the container. What it does not cost: the user, PID, IPC
and network namespaces, the read-only or tmpfs root, the writable-roots list, `--cap-drop ALL`
and the seccomp stage are all still applied, and the user namespace still blocks `/proc/<pid>/`
`root`, `cwd`, `environ` and signals for processes outside the sandbox.

When bumping `CODEX_VERSION`, check whether the issue is closed; if it is, delete the shim, its
`COPY` line in the Dockerfile and this paragraph, rebuild, and confirm the commands below still
pass without it. Verify from inside:

```bash
unshare -Ur true && codex sandbox -- true && echo sandbox-ok
codex sandbox -c 'sandbox_mode="workspace-write"' -- sh -c 'touch .sbx && rm .sbx && touch ~/.sbx' # expect "Read-only file system" and exit 1
```

`make-seccomp.sh` regenerates the file from the current upstream default profile; run it
when Docker's profile changes and commit the result. If you would rather not allow user
namespaces at all, remove the `seccomp=` line from `runArgs` and set
`sandbox_mode = "danger-full-access"` in `config.toml` — the container is the sandbox then.

Known issue, as of 2026-09-20: JetBrains IDEs fail to create the container with `Status 500:
Decoding seccomp profile failed: invalid character '/' looking for beginning of value`. Their
dev-container support passes `runArgs` to the engine API verbatim instead of reading the profile
file the way the `docker` CLI does — [IJPL-67749](https://youtrack.jetbrains.com/issue/IJPL-67749),
open since March 2024. The devcontainer CLI (which VS Code and Codespaces use) hands `runArgs`
to `docker run` unchanged, and the `docker` CLI reads the file itself, so those should be fine —
not yet confirmed by an actual run. To stay in JetBrains until it is fixed, comment out the
`seccomp=` line in `runArgs`; everything else will then work, except for Codex's sandbox — see
the previous paragraph for what to set instead.

Two things you will see that are not errors:

- `Model metadata for '<model>' not found. Defaulting to fallback metadata` at startup. Codex
  keeps a built-in table of per-model metadata (context window, reasoning support, truncation
  policy) keyed by OpenAI model names; a local model is not in it, so generic fallbacks apply.
  The context window is the one value that matters, and it is supplied separately (see below).
  The model name itself does not have to match the server's: a llama-server serving one model
  ignores the `model` field entirely, which is why the `curl` above works with `"model":"local"`.
- `unsupported Responses tool type 'namespace' skipped` (and `'web_search'`) in the server log.
  llama-server drops the Codex tool types it does not implement and carries on.

### Model and context window

Codex cannot ask a provider what it serves or how large its context is — its model metadata
is a static catalog of OpenAI models — and `config.toml` cannot compute values. So `codex` on
`PATH` is a wrapper (`.devcontainer/codex-wrapper.sh`, installed as `~/.local/bin/codex`,
ahead of the real binary) that asks llama-server at launch and passes the answers as
command-line overrides:

```bash
curl -s $LLAMA_SERVER_URL/v1/models | jq -r .data[0].id                  # model id
curl -s $LLAMA_SERVER_URL/props | jq .default_generation_settings.n_ctx   # per-slot n_ctx
codex -c model="<id>" -c model_context_window=<n_ctx>                     # what the wrapper runs
```

The values are read once, when Codex starts; restart Codex after restarting llama-server with
a different model or `-c`. Whatever the wrapper cannot fetch — typically because the server is
not up yet — is left to `config.toml`, which is the only reason `model` and
`model_context_window` are still set there. `specstory run codex` goes through the wrapper
too, since it resolves `codex` via `PATH`. `/usr/local/bin/codex` remains the unwrapped binary
if you ever need it.

The model id is whatever `/v1/models` lists first: the `-a` alias if llama-server was started
with one, otherwise the model's name or path. A server hosting several models (router mode)
lists them all, and "first" is then arbitrary — set `model` in `config.toml` and drop the
`model` line from the wrapper in that case.

## Agent context files

`AGENTS.md` (with `CLAUDE.md` symlinked to it, so Claude Code and Codex read the same file) is
what an agent loads at the start of every session. It is short on purpose; detail lives in
`agent_docs/` and is read on demand. The split matters if you copy `.devcontainer/` elsewhere:

- `.devcontainer/AGENTS.md` and `.devcontainer/agent_docs/` describe life *inside the
  container* — environment quirks, the Codex integration, what a rebuild discards — and travel
  with the directory. In the new project, add one line to your own `AGENTS.md`:
  `@.devcontainer/AGENTS.md` (Claude Code imports it; Codex reads it as a pointer).
- The root `AGENTS.md` and `agent_docs/` are about *this* repository only.

## SpecStory

SpecStory wraps a terminal agent and auto-saves the conversation as markdown under
`.specstory/history/` in the project — your bind-mounted workspace, so transcripts land on
your host and survive the container.

```bash
specstory check          # which agents it can see
specstory run claude     # Claude Code, with auto-save
specstory run codex      # Codex, with auto-save
specstory watch          # save sessions from an agent you start yourself
specstory sync           # convert sessions that already happened in this directory
specstory search <query> # search past sessions
```

All of that is local-only and needs no account; `specstory login` and `specstory skills` are
the cloud (Pro) features.

**Before rebuilding the container, run `specstory sync`.** Agent state lives in the container's
home — `~/.claude`, `~/.codex` — and is not mounted, so it is lost on rebuild. `sync` writes
every Claude Code and Codex session for this directory to `.specstory/history/`, which is on
your host. To be able to *resume* a session afterwards rather than just read it, also copy the
raw transcripts out and back:

```bash
cp -a ~/.claude/projects .claude-backup/                 # before the rebuild (git-ignored)
cp -a .claude-backup/projects ~/.claude/ && claude --resume   # after
```

**Before committing `.specstory/history/`, read it.** Transcripts can contain keys, paths and
internal detail. Only `.specstory/debug/` is git-ignored by default.

## llama-server on the host

The container reaches the host as `host.docker.internal` on every OS.

- **macOS / Windows (Docker Desktop):** works with llama-server bound to `127.0.0.1`. Nothing to do.
- **Linux (native Docker):** `host.docker.internal` resolves to the bridge gateway, which
  cannot reach a loopback-bound process. That gateway is `172.17.0.1` in the common case
  (Docker's default `docker0` bridge, which is what this project's containers use, since
  nothing here defines a custom network) — but it isn't guaranteed: Docker picks a different
  subnet if `172.17.0.0/16` was already taken when Docker was first installed, or if
  `/etc/docker/daemon.json` sets custom `default-address-pools`. Verify it from inside the
  container before copying the commands below verbatim:

  ```bash
  # Run this inside the container:
  getent hosts host.docker.internal
  ```

  If that prints something other than `172.17.0.1`, substitute your actual address in the
  commands that follow. Bind llama-server to that bridge address — still not exposed to your LAN:

  ```bash
  # Run this in the host environment:
  llama-server --host 172.17.0.1 --port 9931   # ...plus your own model/tuning flags
  ```

  A host firewall (e.g. `ufw`) can still block this: binding to `172.17.0.1` is an
  ordinary listening address as far as the kernel's INPUT chain is concerned, and
  Docker does not manage that chain — it only handles traffic it originates itself
  (published container ports, NAT), not a container reaching a host-bound process.
  If `curl` from inside the container times out (not "connection refused") even
  though the port is listening, allow it explicitly, scoped to just the docker
  bridge interface and this address:

  ```bash
  # Run this in the host environment:
  sudo ufw allow in on docker0 to 172.17.0.1 port 9931 proto tcp comment 'Allow access to local llama-server from Docker containers'
  ```

  This persists across reboots like any other `ufw` rule. To remove it later:

  ```bash
  # Run this in the host environment:
  sudo ufw delete allow in on docker0 to 172.17.0.1 port 9931 proto tcp comment 'Allow access to local llama-server from Docker containers'
  ```

  Binding `0.0.0.0` also works but exposes the endpoint to your network; prefer the bridge address.

## Model-specific considerations

Codex was built against OpenAI's models, and a local model's chat template may reject
things Codex sends as a matter of course. The general shape of the problem is described
first; per-model fixes follow in their own sections.

### Mid-conversation developer messages

Codex does not confine system-level instructions to the start of a conversation. It injects
`developer`-role messages between turns whenever its state changes — `Approved command prefix
saved: ["ls"]` after you approve a command, `<turn_context>` after a model or effort switch,
and so on. A chat template that only tolerates system/developer messages at the very
beginning will throw on the next request, and every request after it, since the message is
now part of the history.

Symptoms:

- Codex reports *"We're currently experiencing high demand, which may cause temporary
  errors"* and gives up after five retries. The wording is misleading; it is Codex's generic
  text for any HTTP 500.
- The host log shows the same `got exception: {"error":{"code":500,...}}` repeated every
  second or so — that is the retry loop — and, if you look at the message, a *Jinja
  Exception* naming the guard in the template that fired.

To confirm it is the ordering and not something else, replay the four shapes Codex uses
from inside the container. Only the last one should fail:

```bash
r() { curl -s $LLAMA_SERVER_URL/v1/responses -H "Content-Type: application/json" -d "$1" \
      | jq -c '{status, err: .error.message}'; }
r '{"model":"local","instructions":"Be terse.","input":[{"role":"user","content":"hi"}]}'
r '{"model":"local","input":[{"role":"developer","content":"Be terse."},{"role":"user","content":"hi"}]}'
r '{"model":"local","instructions":"Be terse.","input":[{"role":"developer","content":"x"},{"role":"user","content":"hi"}]}'
r '{"model":"local","input":[{"role":"user","content":"hi"},{"role":"developer","content":"x"},{"role":"user","content":"hi"}]}'
```

You can also see the exact message Codex inserted: sessions are logged as JSONL under
`~/.codex/sessions/`, and this prints every item's role in order:

```bash
jq -c 'select(.type=="response_item") | .payload | {type, role}' ~/.codex/sessions/*/*/*/rollout-*.jsonl
```

The fix is on the host, in the model's chat template: render a late system/developer
message in place instead of raising. `.devcontainer/patch-chat-template.sh` does this generically —
it pulls the live template from the server's `/props`, applies whatever patch it knows for
that template, and writes the result for `--chat-template-file`:

```bash
# From the host, or from the container writing into the bind-mounted workspace:
.devcontainer/patch-chat-template.sh                        # uses $LLAMA_SERVER_URL, writes ./chat-template-patched.jinja
.devcontainer/patch-chat-template.sh http://127.0.0.1:9931 /path/to/out.jinja

# Then, in the host environment:
llama-server ... --chat-template-file /path/to/chat-template-patched.jinja
```

The script only rewrites templates it recognises; if it reports no match, the template is
either already permissive or phrases its guard differently. Find the guard with
`curl -s $LLAMA_SERVER_URL/props | jq -r .chat_template | grep -n raise_exception`, add a
find/replace pair to the `PATCHES` table in the script, and please send it upstream.

Setting `approval_policy = "never"` in `codex-config.toml` avoids the *approved command*
message specifically, but not the other injections, so it is not a substitute for the
template fix.

### Qwen3.8

The Qwen3.8 template merges leading system/developer messages into a single system block
and raises `System message must be at the beginning.` on any later one. The script's
`Qwen3.8` patch replaces that line with an in-place `<|im_start|>system … <|im_end|>` turn,
which is what earlier Qwen templates emitted and which the model handles fine. Nothing else
in the template changes, so tool calling, thinking and reasoning-effort handling are untouched.

## Download verification

Every artifact fetched during the build is authenticated, and every version is pinned —
pinning is what makes a checksum meaningful in the first place.

| Artifact | How it is verified |
|---|---|
| apt packages | GPG signatures on the Debian repo metadata (apt does this itself) |
| uv / uvx | SHA256 from the release's `.tar.gz.sha256`, checked before install |
| SpecStory CLI | SHA256 from the release's `checksums.txt`, checked before install |
| Codex CLI | SHA256 pinned in the Dockerfile — upstream publishes none (see below) |
| Dev container features | Digests in `devcontainer-lock.json`, checked by the devcontainer CLI |
| Base image | Tag only — pin a digest to harden (see below) |

A mismatch fails the build: each `RUN` uses `set -eux` with `sha256sum -c`, so a tampered or
truncated download stops the build rather than being installed.

Codex is the exception that needs care. The `openai/codex` release publishes no `.sha256`
files, so `CODEX_SHA256_AMD64` / `CODEX_SHA256_ARM64` are pinned in the Dockerfile alongside
`CODEX_VERSION` — deliberately *not* exposed as `devcontainer.json` build args, so nobody can
bump the version while leaving stale digests behind. To upgrade, change all three together:

```bash
V=0.156.0
for T in x86_64 aarch64; do
  curl -fsSL "https://github.com/openai/codex/releases/download/rust-v$V/codex-$T-unknown-linux-musl.tar.gz" \
    | sha256sum | sed "s|-|$T|"
done
```

To also pin the base image, resolve its multi-arch digest — the index digest covers every
architecture, so this stays arch-neutral:

```bash
docker buildx imagetools inspect mcr.microsoft.com/devcontainers/base:trixie | head -2
# then: "BASE_IMAGE": "mcr.microsoft.com/devcontainers/base:trixie@sha256:<digest>"
```

Pinning the digest freezes OS security updates until you bump it — worth it for reproducible
builds, but only if you refresh it deliberately.

The two features in `devcontainer.json` (`node`, `claude-code`) are requested by major version
only; `devcontainer-lock.json` records the exact version and digest that were resolved, and the
CLI refuses a feature whose content no longer matches. Commit it. To pick up newer features,
run `devcontainer upgrade --workspace-folder .` (add `--dry-run` to preview), rebuild, and
commit the result.

## Working as root

The container user cannot become root. There is no `sudo` or `doas`, root's password is
locked, every setuid/setgid bit is stripped, and `no-new-privileges` is enforced by the
kernel. Nothing in the container runs as root either, so there is no root process to attack.

When you need root, open a second session **from your host**, where you already have that
authority. Find the container and step in:

```bash
docker ps                                    # find it by image or name
docker exec -it -u root <container> bash
```

Or, from the project folder, in one line:

```bash
docker exec -it -u root "$(docker ps -q -f label=devcontainer.local_folder=$PWD)" bash
```

Then work normally — you are root:

```bash
apt-get update && apt-get install -y <package>
```

This works because the Docker daemon *starts* that shell as root. It is not an escalation
from inside the container, so `no-new-privileges` does not block it, and the agent running
in the container has no way to do the same thing.

**Changes made this way vanish on rebuild.** They are perfect for trying something out; once
you know what you need, move it into the Dockerfile so it survives and stays reproducible.

### Re-enabling sudo (not recommended)

Sudo is off by default. Turning it on takes **two** changes, and both are required:

1. `"ALLOW_SUDO": "true"` in `build.args` in `devcontainer.json`
2. Delete the `"--security-opt=no-new-privileges:true"` line from `runArgs`

Then rebuild. With only the first, sudo is installed but the kernel refuses to let it
elevate — it will fail with a permissions error, which looks like a bug and is not one.

Stripping setuid also disables `su`, `mount`, `fusermount3`, `pkexec` and `passwd` for
everyone in the container. That is the intent; none are needed for normal development.

## Security notes

- Secrets live in `.devcontainer/.env`, which is git-ignored. `.env.example` is the tracked template.
- Codex talks only to your own machine; no model traffic leaves the host unless you add a hosted provider.
- The Docker socket is deliberately **not** mounted; an agent in the container cannot control the host engine.
- No path to root from inside the container, so an agent that goes wrong is confined to the
  `vscode` user and the bind-mounted workspace. The remaining boundary is the container itself —
  harden that further with Docker rootless mode or userns-remap on the host.
- The hardening is enforced at two levels deliberately: the image removes the tools, and
  `no-new-privileges` blocks the whole class of escalation even if a feature or a later
  `apt-get install` puts a setuid binary back.
- The seccomp profile allows unprivileged user namespaces so Codex can sandbox its commands.
  That is the same thing a stock Linux desktop allows, and the container's own boundary is
  unchanged, but it does expose the kernel's user-namespace code to whatever runs inside.
  See *Codex's Linux sandbox* for how to turn it back off.

## Build performance

- BuildKit cache mounts hold apt's `.deb` downloads and package lists between builds.
- Layers are ordered coldest first: apt, then uv, then the pinned SpecStory and Codex downloads.
- `codex-config.toml`, `codex-wrapper.sh` and `bwrap-shim.sh` are copied after the toolchain, so editing them rebuilds only trivial layers.
- `seccomp.json` is a run-time option, not part of the image; changing it needs a container restart, not a rebuild.

## Other architectures

MCR publishes amd64 and arm64 only. For riscv64, set the `BASE_IMAGE` build arg to `debian:trixie`;
the Dockerfile creates the `vscode` user when the base image lacks it. uv ships a `riscv64gc` build
and is installed there too. SpecStory and Codex publish no riscv64 binaries — those steps skip
themselves rather than failing the build, so you get a working container without those two tools.

## License

Apache-2.0 — see [LICENSE.md](LICENSE.md).
