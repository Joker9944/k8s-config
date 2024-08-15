FROM alpine:3.20.2@sha256:0a4eaa0eecf5f8c050e5bba433f58c052be7587ee8af3e8b3910ef9ab5fbe9f5

LABEL org.opencontainers.image.description="Alpine image with postgresql-client installed"

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
