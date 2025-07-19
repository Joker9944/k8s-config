FROM alpine:3.22.1@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1

LABEL org.opencontainers.image.description="Alpine image with postgresql-client installed"

RUN apk add --no-cache postgresql-client

USER nobody:nogroup

ENTRYPOINT ["psql"]
