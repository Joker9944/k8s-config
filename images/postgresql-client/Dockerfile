FROM alpine:3.22.0@sha256:8a1f59ffb675680d47db6337b49d22281a139e9d709335b492be023728e11715

LABEL org.opencontainers.image.description="Alpine image with postgresql-client installed"

RUN apk add --no-cache postgresql-client

USER nobody:nogroup

ENTRYPOINT ["psql"]
