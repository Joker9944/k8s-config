FROM alpine:3.23.0@sha256:51183f2cfa6320055da30872f211093f9ff1d3cf06f39a0bdb212314c5dc7375

LABEL org.opencontainers.image.description="Alpine image with postgresql-client installed"

RUN apk add --no-cache postgresql-client

USER nobody:nogroup

ENTRYPOINT ["psql"]
