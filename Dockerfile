# The exact toolchain behind every result in this repository (also used by CI).
#   docker build -t sv-tools .
#   docker run --rm -v "$PWD":/work sv-tools make ci
FROM ubuntu:26.04@sha256:f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7
COPY scripts/install-tools.sh /tmp/install-tools.sh
RUN bash /tmp/install-tools.sh && rm -rf /var/lib/apt/lists/* /tmp/install-tools.sh
WORKDIR /work
