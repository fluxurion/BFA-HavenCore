# syntax=docker/dockerfile:1.7
# BFA-HavenCore - build multi-stage (EXPERIMENTAL Linux port, ver docker/README.md)

FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc-13 g++-13 cmake ninja-build git ca-certificates pkg-config \
    libboost-all-dev libmysqlclient-dev libssl-dev libbz2-dev libreadline-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

ARG BUILD_JOBS=0
RUN --mount=type=cache,target=/build \
    JOBS=${BUILD_JOBS}; \
    if [ "$JOBS" = "0" ]; then JOBS=$(nproc); fi; \
    cmake -S /src -B /build -G Ninja \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DTOOLS=0 \
      -DSCRIPTS=static \
      -DWITHOUT_GIT=1 \
      -DCMAKE_INSTALL_PREFIX=/opt/bfacore \
    && cmake --build /build -j"$JOBS" \
    && cmake --build /build --target install

# ---------------------------------------------------------------------------

FROM ubuntu:24.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libmysqlclient21 \
    libssl3t64 \
    libreadline8t64 \
    zlib1g \
    libbz2-1.0 \
    libboost-system1.83.0 \
    libboost-filesystem1.83.0 \
    libboost-thread1.83.0 \
    libboost-program-options1.83.0 \
    libboost-iostreams1.83.0 \
    libboost-regex1.83.0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/bfacore /opt/bfacore
COPY docker/entrypoint.sh /opt/bfacore/entrypoint.sh
RUN chmod +x /opt/bfacore/entrypoint.sh

WORKDIR /opt/bfacore/bin
ENTRYPOINT ["/opt/bfacore/entrypoint.sh"]
