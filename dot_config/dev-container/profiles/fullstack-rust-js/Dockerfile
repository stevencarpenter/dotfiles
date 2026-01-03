FROM debian:bookworm-slim

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    openssh-client \
    gnupg \
    pkg-config \
    libssl-dev \
    python3 \
    python3-pip \
    unzip \
    zsh \
    vim \
    gosu \
    procps \
  && rm -rf /var/lib/apt/lists/*

# Node.js 20.x (with GPG verification)
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key -o /tmp/nodesource.gpg.key \
  && gpg --import /tmp/nodesource.gpg.key \
  && curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh \
  && curl -fsSL https://deb.nodesource.com/setup_20.x.asc -o /tmp/nodesource_setup.sh.asc \
  && gpg --trust-model always --verify /tmp/nodesource_setup.sh.asc /tmp/nodesource_setup.sh \
  && bash /tmp/nodesource_setup.sh \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -f /tmp/nodesource.gpg.key /tmp/nodesource_setup.sh /tmp/nodesource_setup.sh.asc \
  && rm -rf /var/lib/apt/lists/*

# Global JS tooling useful for dev
RUN npm install -g npm@latest pnpm@latest vite typescript svelte-language-server

# Create default user; uid/gid will be remapped at runtime by entrypoint
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/zsh "${USERNAME}" \
  && mkdir -p /work

# Rust toolchain
ENV PATH="/home/${USERNAME}/.cargo/bin:${PATH}"
USER ${USERNAME}
# Download rustup installer and verify checksum before running
RUN set -eux; \
  curl -sSfL https://sh.rustup.rs -o /tmp/rustup-init.sh; \
  curl -sSfL https://static.rust-lang.org/rustup/checksums.txt -o /tmp/rustup-checksums.txt; \
  EXPECTED_SHA256="$(awk '$2 == "sh.rustup.rs" {print $1}' /tmp/rustup-checksums.txt)" ; \
  if [ -z "$EXPECTED_SHA256" ]; then \
    echo "Failed to parse expected SHA256 checksum for sh.rustup.rs from rustup-checksums.txt" >&2; \
    exit 1; \
  fi; \
  ACTUAL_SHA256="$(sha256sum /tmp/rustup-init.sh | awk '{print $1}')" ; \
  if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then \
    echo "rustup-init.sh checksum verification failed!" >&2; \
    exit 1; \
  fi; \
  sh /tmp/rustup-init.sh -y --profile minimal; \
  rm -f /tmp/rustup-init.sh /tmp/rustup-checksums.txt; \
  . /home/${USERNAME}/.cargo/env; \
  rustup component add clippy rustfmt rust-analyzer
USER root

WORKDIR /work
COPY common/dev-entrypoint.sh /usr/local/bin/dev-entrypoint
RUN chmod +x /usr/local/bin/dev-entrypoint
ENTRYPOINT ["dev-entrypoint"]
CMD ["/bin/zsh"]
