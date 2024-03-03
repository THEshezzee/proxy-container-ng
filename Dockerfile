FROM docker.io/rapiz1/rathole:latest AS rathole

FROM golang:latest AS sing_box

ENV CGO_ENABLED=0
WORKDIR /go

RUN git clone https://github.com/SagerNet/sing-box.git; cd sing-box \
	&& git checkout $(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

WORKDIR /go/sing-box
RUN set -ex \
    && export COMMIT=$(git rev-parse --short HEAD) \
    && export VERSION=$(go run ./cmd/internal/read_tag) \
    && go build -v -trimpath -tags \
        "with_gvisor,with_quic,with_dhcp,with_wireguard,with_ech,with_utls,with_reality_server,with_acme,with_clash_api" \
        -o /go/bin/sing-box \
        -ldflags "-X \"github.com/sagernet/sing-box/constant.Version=$VERSION\" -s -w -buildid=" \
        ./cmd/sing-box

FROM ubuntu:latest AS dist

COPY --from=rathole /app/rathole /bin/rathole
COPY --from=sing_box /go/bin/sing-box /bin/sing-box

RUN apt update \
	&& apt install -y curl \
	&& curl -fsSL https://tailscale.com/install.sh | sh

RUN rm -rf /var/cache/apt/archives/* \
	/var/cache/apt/archives/partial/

# Healtcheck
RUN rathole --version \
	&& sing-box version \
	&& tailscale version

WORKDIR /app
ENTRYPOINT ["./start.sh"]
# CMD ["tailscale", "version"]
