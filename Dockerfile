FROM docker.io/rapiz1/rathole:latest AS rathole
FROM ghcr.io/akinokaede/asport-client:latest AS asport_client
FROM rustlang/rust:nightly-slim AS shoes
RUN apt-get update && apt-get install -y \
    git \
    pkg-config \
    libssl-dev \
    build-essential \
    clang \
    libclang-dev \
    protobuf-compiler \
    libprotobuf-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/src
RUN git clone --depth 1 https://github.com/cfal/shoes.git
WORKDIR /usr/src/shoes
ENV RUSTFLAGS="--cfg edition2024"
RUN cargo build --release
FROM golang:alpine AS sing_box
ENV CGO_ENABLED=0
WORKDIR /go
RUN apk add git build-base
RUN git clone https://github.com/SagerNet/sing-box.git; cd sing-box \
&& git checkout $(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
WORKDIR /go/sing-box
RUN set -ex \
    && export COMMIT=$(git rev-parse --short HEAD) \
    && export VERSION=$(go run ./cmd/internal/read_tag) \
    && go build -v -trimpath -tags \
        "with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,badlinkname,tfogo_checklinkname0" \
        -o /go/bin/sing-box \
        -ldflags "-X \"github.com/sagernet/sing-box/constant.Version=$VERSION\" -s -w -buildid= -checklinkname=0" \
        ./cmd/sing-box
FROM ghcr.io/yggdrasil-network/yggstack:trunk AS yggstack
FROM ubuntu:latest AS dist
COPY --from=rathole /app/rathole /bin/rathole
COPY --from=sing_box /go/bin/sing-box /bin/sing-box
COPY --from=shoes /usr/src/shoes/target/release/shoes /bin/shoes
COPY --from=asport_client /usr/bin/asport-client /bin/asport-client
COPY --from=yggstack /bin/yggstack /bin/yggstack
RUN apt update \
&& apt install -y curl \
&& curl -fsSL https://tailscale.com/install.sh | sh
RUN rm -rf /var/cache/apt/archives/* \
/var/cache/apt/archives/partial/
# Healthcheck
RUN rathole --version \
&& sing-box version \
&& tailscale version \
&& yggstack --version
WORKDIR /app
ENTRYPOINT ["./start.sh"]
# CMD ["tailscale", "version"]
