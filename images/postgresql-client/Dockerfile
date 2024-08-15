FROM alpine:3.19.3@sha256:95c16745f100f44cf9a0939fd3f357905f845f8b6fa7d0cde0e88c9764060185

RUN apk add --no-cache postgresql-client

ARG PUID=568
ARG PGID=568

RUN \
  addgroup -g "${PGID}" postgresql-client && \
  adduser \
    -u "${PUID}" \
    -G postgresql-client \
    -h /postgresql-client \
    -D \
    postgresql-client

WORKDIR /postgresql-client

USER postgresql-client

ENTRYPOINT ["psql"]
