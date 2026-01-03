FROM python:3.12-slim-bookworm

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
    zsh \
    vim \
    gosu \
    libssl-dev \
    libffi-dev \
    pkg-config \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

# Install uv (astral) globally with checksum verification
# Note: Pin to a specific version and verify checksum for production use
RUN UV_VERSION="0.5.13" && \
  UV_TARGET="x86_64-unknown-linux-gnu" && \
  curl -LsSf "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_TARGET}.tar.gz" -o /tmp/uv.tar.gz && \
  curl -LsSf "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_TARGET}.tar.gz.sha256" -o /tmp/uv.tar.gz.sha256 && \
  cd /tmp && sha256sum -c uv.tar.gz.sha256 && \
  tar -xzf uv.tar.gz && \
  mv uv /usr/local/bin/uv && \
  chmod +x /usr/local/bin/uv && \
  rm /tmp/uv.tar.gz /tmp/uv.tar.gz.sha256
ENV UV_SYSTEM_PYTHON=1

RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/zsh "${USERNAME}" \
  && mkdir -p /work

WORKDIR /work
COPY common/dev-entrypoint.sh /usr/local/bin/dev-entrypoint
RUN chmod +x /usr/local/bin/dev-entrypoint
ENTRYPOINT ["dev-entrypoint"]
CMD ["/bin/zsh"]
