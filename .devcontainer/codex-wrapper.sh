#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
# SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
# SPDX-License-Identifier: Apache-2.0
#
# Installed as ~/.local/bin/codex, ahead of the real binary on PATH, so it also catches
# `specstory run codex`. Codex has no way to ask a custom provider what it serves or how
# large its context is, and its config.toml cannot compute values, so this asks llama-server
# at launch and passes the answers as -c overrides: the model id from /v1/models and the
# per-slot n_ctx from /props. Whatever it cannot fetch is left to config.toml's fallback
# values. Everything else passes through to the real binary.
set -euo pipefail

real=/usr/local/bin/codex
if [ ! -x "$real" ]; then
  echo "codex: $real is not installed (no Codex binary for this architecture?)" >&2
  exit 127
fi

server="${LLAMA_SERVER_URL:-http://host.docker.internal:9931}"
fetch() { curl -fsS --max-time 2 "$server$1" 2>/dev/null | jq -r "$2 // empty" 2>/dev/null || true; }

model=$(fetch /v1/models '.data[0].id')
n_ctx=$(fetch /props '.default_generation_settings.n_ctx')

overrides=()
[ -n "$model" ] && overrides+=(-c "model=\"$model\"")   # quoted: -c values are parsed as TOML
[ -n "$n_ctx" ] && overrides+=(-c "model_context_window=$n_ctx")

exec "$real" "${overrides[@]}" "$@"
