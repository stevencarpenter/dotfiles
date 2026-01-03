FROM openjdk:17-jdk-slim

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
ARG SPARK_VERSION=3.5.1
ARG HADOOP_VERSION=3

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    python3 \
    python3-pip \
    python3-venv \
    scala \
    zsh \
    vim \
    gosu \
    procps \
    wget \
    tar \
    coreutils \
    gnupg \
  && rm -rf /var/lib/apt/lists/*

# Apache Spark with GPG and checksum verification
RUN mkdir -p /opt \
  && curl -fsSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" -o /tmp/spark.tgz \
  && curl -fsSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz.sha512" -o /tmp/spark.tgz.sha512 \
  && curl -fsSL "https://downloads.apache.org/spark/KEYS" -o /tmp/KEYS \
  && curl -fsSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz.asc" -o /tmp/spark.tgz.asc \
  && gpg --import /tmp/KEYS \
  && gpg --verify /tmp/spark.tgz.asc /tmp/spark.tgz \
  && sha512sum -c /tmp/spark.tgz.sha512 \
  && tar -xzf /tmp/spark.tgz -C /opt \
  && mv "/opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}" /opt/spark \
  && rm /tmp/spark.tgz /tmp/spark.tgz.sha512 /tmp/spark.tgz.asc /tmp/KEYS

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}"

# Align PySpark with shipped Spark
RUN python3 -m pip install --no-cache-dir "pyspark==${SPARK_VERSION}"

RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/zsh "${USERNAME}" \
  && mkdir -p /work

WORKDIR /work
COPY common/dev-entrypoint.sh /usr/local/bin/dev-entrypoint
RUN chmod +x /usr/local/bin/dev-entrypoint
ENTRYPOINT ["dev-entrypoint"]
CMD ["/bin/zsh"]
