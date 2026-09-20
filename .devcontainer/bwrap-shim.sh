#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
# SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
# SPDX-License-Identifier: Apache-2.0

# TEMPORARY WORKAROUND — remove once https://github.com/openai/codex/issues/44329 is fixed.
# Delete this file, its COPY line in the Dockerfile and the README paragraph that names it.
# Check on a Codex bump: with the shim gone, `codex sandbox -- true` must still succeed.
#
# Installed as /usr/local/bin/bwrap, ahead of /usr/bin/bwrap on PATH, so Codex's Linux
# sandbox finds it first.
#
# Codex asks bubblewrap for a fresh procfs (`--proc /proc`). Docker masks parts of the
# container's /proc (/proc/kcore, /proc/sys, ...), and the kernel then refuses to mount a
# new procfs from an unprivileged user namespace: "Can't mount proc on /proc: Operation not
# permitted". Codex has a fallback for exactly this (`--no-proc`), but it recognises the
# failure only by bubblewrap's pre-0.12 wording ("/newroot/proc"); Debian 13 ships 0.12.0.
# See https://github.com/openai/codex/issues/44329.
#
# This shim makes the same decision Codex would: if the kernel refuses a fresh procfs, drop
# `--proc <dest>` and run the sandbox with the container's /proc instead. Everything else
# (user/pid/ipc/net namespaces, read-only or tmpfs root, cap-drop, seccomp) is untouched,
# and the real bubblewrap is exec'd so PIDs, signals and inherited fds are unchanged.
set -euo pipefail

real=/usr/bin/bwrap

want_proc=false
for arg in "$@"; do
  [[ "$arg" == "--" ]] && break
  [[ "$arg" == "--proc" ]] && want_proc=true
done

if [[ "$want_proc" == true ]] \
   && ! "$real" --unshare-user --unshare-pid --ro-bind / / --proc /proc -- /bin/true 2>/dev/null; then
  args=()
  skip=false
  for arg in "$@"; do
    if [[ "$skip" == true ]]; then skip=false; continue; fi
    if [[ "$arg" == "--proc" ]]; then skip=true; continue; fi
    args+=("$arg")
  done
  exec "$real" "${args[@]}"
fi

exec "$real" "$@"
