# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: 2026 Volkert de Buisonjé <volkertb@users.noreply.github.com>
# SPDX-FileContributor: Claude Opus 5 <noreply@anthropic.com>
# SPDX-License-Identifier: Apache-2.0

# BuildKit syntax directive: required for the cache mounts used below.

# Debian 13 "trixie" devcontainer base: ships git and the `vscode` user (uid 1000).
# Its bundled sudo is removed further down unless ALLOW_SUDO=true.
# Swap for `debian:trixie` (or any Debian/Ubuntu image) on architectures MCR does not build, e.g. riscv64.
ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/base:trixie
FROM ${BASE_IMAGE}

ARG USERNAME=vscode
ARG INSTALL_UV=true
# false (default): no sudo, no setuid path to root. See "Working as root" in the README.
ARG ALLOW_SUDO=false
# Pinned: a fixed version is what makes the published checksum verifiable.
ARG UV_VERSION=0.12.17
ARG SPECSTORY_VERSION=2.13.0
# Codex version and digests are kept together deliberately — bumping one without
# the others must fail the build, so they are not exposed as devcontainer.json args.
ARG CODEX_VERSION=0.155.1
ARG CODEX_SHA256_AMD64=a0ef8b2debc3bf747e07b1a039354de31300ac0dcc2276498ba281470b5d9115
ARG CODEX_SHA256_ARM64=d6c7e62fbd688d52ee04f3929d0613705d32a920a42db7a139e366eaf1f4a2d7
ENV DEBIAN_FRONTEND=noninteractive

# Docker's base images auto-purge the apt cache after every install.
# Disabling that is what lets the cache mounts below survive between builds.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
 && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Create the user when the base image has no such account (plain debian:trixie).
# No-op on the MCR base image, which already ships it.
RUN if ! id -u "${USERNAME}" >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends ca-certificates \
      && groupadd --gid 1000 "${USERNAME}" \
      && useradd --uid 1000 --gid 1000 -m -s /bin/bash "${USERNAME}"; \
    fi

# Baseline toolchain agents reach for: compilers, Python, search/inspection tools, archives, net utils.
# Cache mounts keep the .deb downloads and package lists outside the image layer.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build pkg-config gdb strace ltrace \
      python3 python3-dev python3-venv python3-pip pipx \
      git git-lfs curl wget ca-certificates gnupg openssh-client rsync \
      jq ripgrep fd-find fzf bat tree less file vim nano \
      unzip zip tar gzip bzip2 xz-utils zstd p7zip-full \
      bash-completion man-db manpages locales tmux htop procps psmisc lsof \
      iproute2 iputils-ping dnsutils netcat-openbsd socat \
      sqlite3 bc patch diffutils moreutils shellcheck

# Debian ships these under alternative names; agents expect the upstream ones.
RUN ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
 && ln -sf "$(command -v batcat)" /usr/local/bin/bat

# uv: fast Python package/venv manager, pinned and checksum-verified rather than
# piped from an installer script. Skipped where upstream publishes no binary.
RUN set -eux; \
    if [ "${INSTALL_UV}" != "true" ]; then exit 0; fi; \
    case "$(dpkg --print-architecture)" in \
      amd64)   UV_TARGET=x86_64-unknown-linux-gnu ;; \
      arm64)   UV_TARGET=aarch64-unknown-linux-gnu ;; \
      riscv64) UV_TARGET=riscv64gc-unknown-linux-gnu ;; \
      *) echo "No uv binary for $(dpkg --print-architecture); skipping."; exit 0 ;; \
    esac; \
    BASE="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}"; \
    cd /tmp; \
    curl -fsSL -o uv.tgz "${BASE}/uv-${UV_TARGET}.tar.gz"; \
    curl -fsSL -o uv.sha "${BASE}/uv-${UV_TARGET}.tar.gz.sha256"; \
    sed "s|uv-${UV_TARGET}.tar.gz|uv.tgz|" uv.sha | sha256sum -c -; \
    tar xzf uv.tgz --strip-components=1 -C /usr/local/bin \
      "uv-${UV_TARGET}/uv" "uv-${UV_TARGET}/uvx"; \
    chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx; \
    rm -f uv.tgz uv.sha

# SpecStory CLI: single Go binary, checksum-verified against the published manifest.
# Skipped where upstream publishes no binary rather than failing the build.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) SS_ARCH=x86_64 ;; \
      arm64) SS_ARCH=arm64 ;; \
      *) echo "No SpecStory binary for $(dpkg --print-architecture); skipping."; exit 0 ;; \
    esac; \
    BASE="https://github.com/specstoryai/getspecstory/releases/download/v${SPECSTORY_VERSION}"; \
    cd /tmp; \
    curl -fsSL -o ss.tgz "${BASE}/SpecStoryCLI_Linux_${SS_ARCH}.tar.gz"; \
    curl -fsSL -o ss.sha "${BASE}/SpecStoryCLI_${SPECSTORY_VERSION}_checksums.txt"; \
    grep "SpecStoryCLI_Linux_${SS_ARCH}.tar.gz" ss.sha \
      | sed "s|SpecStoryCLI_Linux_${SS_ARCH}.tar.gz|ss.tgz|" | sha256sum -c -; \
    tar xzf ss.tgz -C /usr/local/bin specstory; \
    chmod 0755 /usr/local/bin/specstory; \
    rm -f ss.tgz ss.sha

# Codex CLI: static musl binary from the openai/codex GitHub release.
# Upstream publishes no .sha256, so the digests are pinned here and must be
# updated together with CODEX_VERSION:
#   curl -fsSL <asset-url> | sha256sum
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) CODEX_TARGET=x86_64-unknown-linux-musl;  CODEX_SHA="${CODEX_SHA256_AMD64}" ;; \
      arm64) CODEX_TARGET=aarch64-unknown-linux-musl; CODEX_SHA="${CODEX_SHA256_ARM64}" ;; \
      *) echo "No Codex binary for $(dpkg --print-architecture); skipping."; exit 0 ;; \
    esac; \
    cd /tmp; \
    curl -fsSL -o codex.tgz \
      "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${CODEX_TARGET}.tar.gz"; \
    echo "${CODEX_SHA}  codex.tgz" | sha256sum -c -; \
    tar xzf codex.tgz; \
    mv "codex-${CODEX_TARGET}" /usr/local/bin/codex; \
    chmod 0755 /usr/local/bin/codex; \
    rm -f codex.tgz

# TEMPORARY: remove together with bwrap-shim.sh once openai/codex#44329 is fixed upstream.
# Codex's sandbox asks bubblewrap for a fresh /proc, which the kernel refuses under Docker's
# masked /proc. Codex has a `--no-proc` fallback but misses bubblewrap >= 0.12's error wording,
# so this shim, first on PATH, makes that decision instead.
COPY --chmod=0755 bwrap-shim.sh /usr/local/bin/bwrap

# Privilege hardening, last so it also strips anything the steps above installed.
# Default strips every setuid/setgid bit and locks root, leaving no in-container path to root.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    if [ "${ALLOW_SUDO}" = "true" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends sudo; \
      echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"; \
      chmod 0440 "/etc/sudoers.d/${USERNAME}"; \
    else \
      apt-get purge -y sudo || true; \
      rm -rf /etc/sudoers /etc/sudoers.d /usr/bin/sudo /usr/bin/doas /usr/local/bin/sudo; \
      passwd -l root; \
      find / -xdev -perm /6000 -type f -exec chmod ug-s {} +; \
    fi

# Points Codex at the host's llama-server. Edit this file to change model or endpoint.
COPY --chown=${USERNAME}:${USERNAME} codex-config.toml /home/${USERNAME}/.codex/config.toml

# SpecStory defaults for every project (cloud sync and analytics off). Shipped at build time
# because ~/.specstory is not persisted; a project's .specstory/cli/config.toml overrides it.
COPY --chown=${USERNAME}:${USERNAME} specstory-config.toml /home/${USERNAME}/.specstory/cli/config.toml

# `codex` on PATH resolves to this wrapper (~/.local/bin precedes /usr/local/bin below),
# which passes llama-server's actual context size to the real binary at launch.
COPY --chown=${USERNAME}:${USERNAME} --chmod=0755 codex-wrapper.sh /home/${USERNAME}/.local/bin/codex

# Default lives here, not in containerEnv, so .env (docker --env-file) can override it.
# Codex itself reads config.toml; this is for ad-hoc checks and other tools.
ENV LLAMA_SERVER_URL=http://host.docker.internal:9931 \
    PATH=/home/${USERNAME}/.local/bin:${PATH}

USER ${USERNAME}
