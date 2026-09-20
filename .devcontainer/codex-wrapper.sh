#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
# SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
# SPDX-License-Identifier: Apache-2.0
#
# Installed as ~/.local/bin/codex, ahead of the real binary on PATH, so it also catches
# `specstory run codex`. Codex has no way to ask a custom provider for its context size
# and its config.toml cannot compute values, so this reads llama-server's per-slot n_ctx
# at launch and passes it as a -c override. If the server is not reachable, Codex starts
# with the model_context_window from config.toml instead. Everything else passes through.
set -euo pipefail

real=/usr/local/bin/codex
if [ ! -x "$real" ]; then
  echo "codex: $real is not installed (no Codex binary for this architecture?)" >&2
  exit 127
fi

n_ctx=$(curl -fsS --max-time 2 "${LLAMA_SERVER_URL:-http://host.docker.internal:9931}/props" 2>/dev/null \
        | jq -r '.default_generation_settings.n_ctx // empty' 2>/dev/null || true)

if [ -n "$n_ctx" ]; then
  exec "$real" -c "model_context_window=$n_ctx" "$@"
fi
exec "$real" "$@"
