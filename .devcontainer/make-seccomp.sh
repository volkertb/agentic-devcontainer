#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
# SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
# SPDX-License-Identifier: Apache-2.0
#
# Regenerates seccomp.json: Docker's default seccomp profile, plus the syscalls bubblewrap
# needs to build an unprivileged user-namespace sandbox (what Codex's Linux sandbox uses).
# The default profile allows these only with CAP_SYS_ADMIN, which the container does not
# have. Run this to pick up upstream changes to the default profile; the output is committed.
#
# Usage: .devcontainer/make-seccomp.sh   (needs curl and jq)
set -euo pipefail

cd "$(dirname "$0")"
src=https://raw.githubusercontent.com/moby/profiles/main/seccomp/default.json
allow='["unshare","clone","mount","umount2","pivot_root","setns"]'

curl -fsSL "$src" | jq --argjson allow "$allow" '
  # Drop the syscalls from every existing rule (the CAP_SYS_ADMIN-gated ones and the
  # flag-masked clone rules), remove rules left empty, then allow them unconditionally.
  .syscalls |= map(.names -= $allow | select(.names | length > 0))
  | .syscalls += [{
      names: $allow,
      action: "SCMP_ACT_ALLOW",
      comment: "Unprivileged user namespaces for bubblewrap (Codex sandbox). Added by make-seccomp.sh."
    }]
' > seccomp.json

echo "Wrote $(pwd)/seccomp.json from $src"
