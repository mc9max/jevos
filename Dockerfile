# syntax=docker/dockerfile:1
# ============================================================================
# Railway Template: JevOS (feder-cr/jev)
# ----------------------------------------------------------------------------
# Open-source, CPU-only alternative to TypeSafe Jev for yes/no decisions.
# The single static `jev` binary runs jevos-v3 (MiniCPM5-1B -> 17 layers,
# one-logit head) through Intel OpenVINO INT8 weights on the CPU only --
# no Python, no GPU, fully offline once the container is up. It speaks
# TypeSafe Jev's wire format (POST /v1/systemone -> noul = P(yes)).
#
# The binary + OpenVINO/TBB shared libs + the int8 model are pulled from the
# pinned `jevos-v3` release at BUILD time and verified by SHA-256 against the
# release's SHA256SUMS.txt. The model is ~630 MB so it is baked into the
# image (it is far over GitHub's 100 MB per-file limit and cannot live in the
# template repo). After the image is pulled the service needs no network.
# ============================================================================

ARG BASE=debian:trixie-slim

# ---------------------------------------------------------------- build ----
FROM ${BASE} AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils unzip \
 && rm -rf /var/lib/apt/lists/*

# Pinned release -- bump this to move jevos versions (binary + model ship
# together under the same tag).
ARG JEVERSION=jevos-v3
# Integrity pins from the release's SHA256SUMS.txt (verified 2026-10-04).
ARG JEV_BIN_SHA256=09a85acf942c92d068bfc455f6bd4b61f4282a09848abd81998c59262c3aafd7
ARG JEV_MODEL_SHA256=f473c3793fd02566b3c53a7c2b1e8fe223aa3763e7c51222f596bed433b22b75

WORKDIR /src
RUN set -eux; \
    curl -fsSL --retry 3 -o jev.tgz \
        "https://github.com/feder-cr/jev/releases/download/${JEVERSION}/jev-linux-x64.tar.gz"; \
    echo "${JEV_BIN_SHA256} *jev.tgz" | sha256sum -c -; \
    echo "=== binary assets ==="; \
    tar tzf jev.tgz

RUN set -eux; \
    mkdir -p /out; \
    tar xzf /src/jev.tgz -C /out; \
    curl -fsSL --retry 3 -o /src/jevos-openvino.zip \
        "https://github.com/feder-cr/jev/releases/download/${JEVERSION}/jevos-v3-openvino-int8.zip"; \
    echo "${JEV_MODEL_SHA256} */src/jevos-openvino.zip" | sha256sum -c -; \
    # zip root is `model/` -> lands next to the binary (binary default = <dir>/model)
    unzip -q /src/jevos-openvino.zip -d /out/jev; \
    echo "=== final layout ($(du -sh /out/jev | cut -f1)) ==="; \
    ls -la /out/jev /out/jev/model

# ----------------------------------------------------------------- final --
FROM ${BASE}
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 libgcc-s1 ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
# curl = in-image HEALTHCHECK probe. (Runtime needs only the C++ runtime for
# the jev binary; OpenVINO + TBB are the libs from the release, copied below.)
ENV LD_LIBRARY_PATH=/opt/jev \
    PORT=8080 \
    TZ=UTC
COPY --from=build /out/jev /opt/jev
# entrypoint.sh (assembles `jev serve` from env) -- from this repo, not the release.
COPY entrypoint.sh /opt/jev/entrypoint.sh
# Co-locate binary + libs + model (the layout jev was proven with). Non-root:
# nothing is volume-mounted, so the root-owned-volume EACCES trap doesn't apply.
RUN chown -R 1000:1000 /opt/jev \
 && chmod -R a+rX  /opt/jev \
 && useradd -u 1000 -r -s /usr/sbin/nologin jevoc 2>/dev/null || true
USER 1000
WORKDIR /opt/jev

# jev speaks TypeSafe's wire format on $PORT; /health is the Railway check.
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=8s --start-period=90s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/health" >/dev/null 2>&1 || exit 1

# entrypoint.sh assembles `jev serve` from env (PORT, JEV_API_KEY, then the
# optional JEV_THREADS / JEV_CTX knobs; blank = the release's tested default).
CMD ["sh", "/opt/jev/entrypoint.sh"]
