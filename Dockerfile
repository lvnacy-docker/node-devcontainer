# syntax=docker/dockerfile:1
#
# ============================================================
# Stage 1: builder — installs mise, Node 24, pnpm 12
# ============================================================
FROM debian:13-slim AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- mise, pinned ------------------------------------------------------
# Pin the version instead of always grabbing "latest" — `curl | sh` on a
# moving target is how you end up debugging this exact class of problem
# again in six months. Bump this deliberately when you want to upgrade.
ARG MISE_VERSION=v2026.9.5

# System-level dirs (NOT under $HOME). This matters for devcontainers:
# VS Code frequently bind-mounts or overlays parts of the user's home
# directory, and anything mise installed under ~/.local/share/mise would
# get silently hidden behind that mount. Keeping mise's data/config/cache
# under /usr/local means it survives regardless of what gets mounted over
# /home/vscode later. See: https://mise.jdx.dev/mise-cookbook/docker.html
ENV MISE_DATA_DIR=/usr/local/share/mise
ENV MISE_CONFIG_DIR=/usr/local/share/mise
ENV MISE_CACHE_DIR=/usr/local/share/mise/cache
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV PATH="/usr/local/share/mise/shims:/usr/local/bin:${PATH}"

RUN curl --proto '=https' --proto-redir '=https' \
        --fail --show-error --silent --location https://mise.run | sh

# --- toolchain -----------------------------------------------------------
# mise installs pnpm straight from pnpm's own release binaries (the aqua
# backend) rather than piping get.pnpm.io/install.sh through a shell.
# `mise use --global` both installs the tools AND writes the version
# pins into $MISE_CONFIG_DIR/config.toml, so every shell — interactive or
# not — resolves the same versions with zero extra config.
RUN mise use --global node@24 pnpm@12 \
    && mise reshim

# --- TypeScript 7, global ------------------------------------------------
# TS7 (the Go-native compiler, stable since July 2026) is installed
# globally for Tab Candy's fast typecheck path, with TS5 handled
# per-project in node_modules for everything TS7 doesn't fully support yet.
#
# `npm install -g` normally drops files next to whichever node binary is
# active — which here would be somewhere under mise's install dir. That's
# fragile: it only resolves at runtime if the calling shell has mise
# properly activated (fine in an interactive terminal, NOT guaranteed for
# devcontainer postCreateCommand/postStartCommand, which run as a plain
# non-interactive shell). Forcing NPM_CONFIG_PREFIX=/usr/local instead
# drops `tsc` straight into /usr/local/bin, which is unconditionally on
# PATH — no activation, no shim lookup, no ambiguity.
ENV NPM_CONFIG_PREFIX=/usr/local
RUN mise exec -- npm install -g typescript@^7

# Sanity-check the toolchain actually resolves before we ship it.
RUN node --version && pnpm --version && tsc --version

# ============================================================
# Stage 2: runtime — minimal, non-root
# ============================================================
FROM debian:13-slim AS runtime

# Only what's needed to actually run/dev against Node + pnpm inside the
# container. git and bash are functional requirements for a devcontainer
# (VS Code's remote server needs a real shell; you'll want git in your
# terminal), not just "nice to have."
#
# NOTE ON DISTROLESS: I'd steer away from it here. VS Code Remote/Dev
# Containers injects and runs its own server process inside the
# container over SSH-less exec, which needs a POSIX shell, tar, and
# coreutils to unpack and stay alive — exactly what distroless images
# deliberately strip out. Distroless is a great choice for the
# *production* image you eventually build from this same repo; it's a
# poor fit for the interactive devcontainer itself. This stage gets you
# the same hardening benefit (small final image, no build tooling, no
# package manager binaries left lying around) without breaking the IDE.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        git \
        ca-certificates \
        libatomic1 \
        libstdc++6 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
               /usr/share/doc/* /usr/share/man/* /usr/share/locale/* \
               /tmp/* /var/tmp/* \
    # Remove apt/dpkg binaries so nothing in the running container can
    # install more packages at runtime (leave the dpkg database intact
    # so `dpkg -l` still works for auditing).
    && rm -f /usr/bin/apt* /usr/bin/dpkg* \
    && rm -rf /etc/apt /var/lib/{apt,cache,log}

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    # No interactive root account in the running container.
    && passwd -l root \
    && usermod -s /usr/sbin/nologin root

# Pre-create (and own) every path under $HOME that pnpm/mise will need to
# write at container *runtime*, before anything gets mounted over it.
#
# This matters specifically because devcontainer.json mounts a named
# volume at /home/vscode/.local/share/pnpm/store. If that directory
# doesn't already exist in the image, Docker creates it — and its
# missing parents (.local, .local/share) — as root the first time the
# volume attaches. Every *other* thing living under .local (mise's
# tracked-configs state, pnpm's virtual-store) then inherits a
# non-writable root-owned ancestor and fails with EACCES, even though it
# has nothing to do with the volume itself.
#
# Creating and chowning the full tree here means: (a) vscode owns the
# parents before Docker ever needs to auto-create them, and (b) Docker's
# volume "copy-up" behavior seeds the fresh named volume with this
# directory's existing ownership, so the mounted store itself is
# writable too.
RUN mkdir -p \
      /home/$USERNAME/.local/share/pnpm/store \
      /home/$USERNAME/.local/share/pnpm/virtual-store \
      /home/$USERNAME/.local/state/mise \
    && chown -R $USERNAME:$USERNAME /home/$USERNAME

# Everything mise installed lives under /usr/local, owned by root —
# the vscode user only ever needs read+execute here, never write, so
# there's no COPY --chown needed and no risk of the dev user tampering
# with the toolchain.
COPY --from=builder /usr/local/share/mise /usr/local/share/mise
COPY --from=builder /usr/local/bin/mise /usr/local/bin/mise
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/tsc /usr/local/bin/tsc

# Exception to "read-only": mise's cache dir isn't build-time-immutable
# toolchain data, it's a runtime scratch space mise rewrites every time a
# shim resolves a tool (bin-path lookups, etc). Locking it down alongside
# installs/shims/config was too broad — reset and re-own just this one
# subdirectory so mise can actually use it, without giving vscode write
# access to the installed binaries or config.toml next to it.
RUN rm -rf /usr/local/share/mise/cache \
    && mkdir -p /usr/local/share/mise/cache \
    && chown -R $USERNAME:$USERNAME /usr/local/share/mise/cache

ENV MISE_DATA_DIR=/usr/local/share/mise
ENV MISE_CONFIG_DIR=/usr/local/share/mise
ENV MISE_CACHE_DIR=/usr/local/share/mise/cache
ENV PNPM_HOME=/home/$USERNAME/.local/share/pnpm
ENV PATH="/usr/local/share/mise/shims:/usr/local/bin:$PNPM_HOME:${PATH}"

# Interactive-shell niceties (so `mise` env/task features work in a
# terminal, not just the baked-in shim PATH above).
RUN { \
      echo 'export PATH="/usr/local/share/mise/shims:/usr/local/bin:$PNPM_HOME:$PATH"'; \
      echo 'eval "$(mise activate bash)"'; \
    } | tee -a /home/$USERNAME/.bashrc /home/$USERNAME/.profile >/dev/null \
    && chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc /home/$USERNAME/.profile

USER $USERNAME
WORKDIR /workspace

CMD ["/bin/bash"]