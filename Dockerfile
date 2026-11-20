FROM golang:bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends git gcc libc6-dev ca-certificates \
 && git clone --depth 1 https://github.com/XTLS/Xray-core.git /src
WORKDIR /src
RUN CGO_ENABLED=1 go build -trimpath -buildmode=pie -tags netgo \
    -ldflags "-s -w -buildid= -linkmode external -extldflags -static-pie" \
    -o /xray ./main

FROM scratch
COPY --from=build /xray /usr/bin/xray
COPY config.json /etc/xray/config.json
