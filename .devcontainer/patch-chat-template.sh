#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
# SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
# SPDX-License-Identifier: Apache-2.0
#
# Fetch the chat template from a running llama-server and patch it so it accepts
# system/developer messages that appear mid-conversation, which agent clients such
# as Codex CLI inject and which some models' templates reject with a Jinja exception.
#
# The workflow is model-neutral (fetch, patch, tell you how to load it); the actual
# patches are per-model string replacements in the PATCHES table below, because each
# model's template phrases its guard differently. Add an entry for a new model there.
#
# Usage: .devcontainer/patch-chat-template.sh [SERVER_URL] [OUT_FILE]
#   SERVER_URL  defaults to $LLAMA_SERVER_URL, else http://127.0.0.1:9931
#   OUT_FILE    defaults to ./chat-template-patched.jinja
#
# Runs on the host or in the container; only needs curl and jq. The output file must end
# up where the host-side llama-server can read it (the bind-mounted workspace works).
set -euo pipefail

url="${1:-${LLAMA_SERVER_URL:-http://127.0.0.1:9931}}"
out="${2:-chat-template-patched.jinja}"

# Each patch is a pair: literal text to find, literal text to replace it with.
# Keep both sides exact — this is plain string substitution, no regex.
PATCHES=(
  # Qwen3.8: renders leading system/developer messages as one system block, then raises on
  # any later one. Emit a system turn in place instead (what earlier Qwen templates did).
  "Qwen3.8 mid-conversation system message"
  "{{- raise_exception('System message must be at the beginning.') }}"
  "{{- '<|im_start|>system\\n' + content + '<|im_end|>' + '\\n' }}"
)

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "error: $tool is required" >&2; exit 1; }
done

echo "Fetching chat template from $url/props"
template="$(curl -fsS "$url/props" | jq -r '.chat_template // empty')"
if [ -z "$template" ]; then
  echo "error: no chat_template in $url/props (is llama-server running there?)" >&2
  exit 1
fi

applied=0
for ((i = 0; i < ${#PATCHES[@]}; i += 3)); do
  name="${PATCHES[i]}" find="${PATCHES[i+1]}" replace="${PATCHES[i+2]}"
  case "$template" in
    *"$find"*)
      template="${template//"$find"/"$replace"}"
      echo "Applied patch: $name"
      applied=$((applied + 1))
      ;;
  esac
done

if [ "$applied" -eq 0 ]; then
  echo "No known patch matches this template; nothing written." >&2
  echo "Inspect its guards with:  curl -s $url/props | jq -r .chat_template | grep -n raise_exception" >&2
  exit 2
fi

printf '%s' "$template" > "$out"   # no added newline: it would leak into the prompt
echo "Wrote $out"
echo
echo "Restart llama-server with the patched template (path as seen from the host):"
echo "  llama-server ... --chat-template-file $out"
