<!--
SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
SPDX-License-Identifier: Apache-2.0
-->

# Codex ↔ llama-server: how it fits together

The source project's README → *Codex and llama-server* and *Model-specific considerations*
are the full account. This is the map, the things that look like errors and are not, and the probes.

## Moving parts

- `codex-config.toml` → `~/.codex/config.toml` at build time. `model` and `model_context_window`
  there are **fallbacks only**.
- `codex-wrapper.sh` → `~/.local/bin/codex`, ahead of `/usr/local/bin/codex`. At launch it reads
  `/v1/models` (model id) and `/props` (per-slot `n_ctx`) and passes `-c` overrides. Values are
  read once per launch. `specstory run codex` also goes through it.
- `seccomp.json` (via `runArgs`) → lets bubblewrap create user namespaces so Codex's sandbox
  works. Regenerate with `make-seccomp.sh`; it is Docker's default + `unshare clone mount
  umount2 pivot_root setns`.
- `patch-chat-template.sh` → host-side fix for templates that reject Codex's mid-conversation
  `developer` messages. Output goes to `--chat-template-file` on the host.

## Failure modes seen so far

| Symptom | Cause | Fix |
|---|---|---|
| Host log: repeated 500 with *Jinja Exception: System message must be at the beginning*; Codex says *high demand* | Codex injected a `developer` message after user turns (e.g. after a command approval); Qwen3.8 template raises | `patch-chat-template.sh`, restart llama-server with the output |
| `bwrap: No permissions to create a new namespace` / *needs access to create user namespaces* | Docker default seccomp blocks `unshare`/`mount`/`pivot_root` | `seccomp.json` in `runArgs`; needs recreate |
| Codex thinks context is 32768 while server has more | Wrapper not on PATH, or server unreachable at launch | `which codex` must be `~/.local/bin/codex`; restart Codex |

## Not errors

- `Model metadata for '<model>' not found. Defaulting to fallback metadata` — the model isn't
  in Codex's compiled-in OpenAI catalog. Unfixable without lying about the model name; harmless
  since the wrapper supplies the context window.
- `unsupported Responses tool type 'namespace' skipped` / `'web_search'` in the server log —
  Codex tool types llama-server doesn't implement. Nothing to do with Linux namespaces.
- *"Codex's Linux sandbox uses bubblewrap…"* — same as the bwrap row above, before the recreate.

## Probes (from inside the container)

```bash
curl -s $LLAMA_SERVER_URL/v1/models | jq -r .data[0].id                  # model id the wrapper passes
curl -s $LLAMA_SERVER_URL/props | jq .default_generation_settings.n_ctx   # context the wrapper passes
curl -s $LLAMA_SERVER_URL/props | jq -r .chat_template | grep -n raise_exception   # template guards
codex exec -s read-only "Reply with the single word OK"                   # end-to-end (not --json: waits on stdin)
unshare -Ur true && codex sandbox -- true && echo sandbox-ok              # sandbox works
```

The four-shape Responses probe for message-ordering failures is in the README →
*Model-specific considerations*. To see what Codex actually sent:

```bash
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head -1)
jq -c 'select(.type=="response_item") | .payload | {type, role}' "$f"          # roles in order
jq -c 'select(.type=="event_msg") | .payload | select(.type=="token_count") | .info.model_context_window' "$f" | tail -1
```

Codex reports `model_context_window` minus its own reserve (98304 → 93388, 32768 → 31129).
