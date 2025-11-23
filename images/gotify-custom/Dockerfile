FROM alpine:3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412 AS downloader

ARG TARGETARCH
# renovate: datasource=github-releases depName=gotify-slack-webhook packageName=LukasKnuth/gotify-slack-webhook versioning=semver-coerced
ARG GOTIFY_SLACK_WEBHOOK_VERSION=2025.11.1
ARG GOTIFY_SLACK_WEBHOOK_SHA256_AMD64="c139acfddfa9190156f2fd644c3b4069262ad53e65c2bca80e3ff3a37bfbc248"
ARG GOTIFY_SLACK_WEBHOOK_SHA256_ARM64="5c53897aa38ec9a6cb6b486817f6857179ffaf3af0a853817c58800a3c9c2e72"

# Setup
RUN apk add --no-cache curl coreutils \
 && mkdir -p /downloads

WORKDIR /downloads

# Download
RUN wget -qO gotify-slack-webhook.so "https://github.com/LukasKnuth/gotify-slack-webhook/releases/download/${GOTIFY_SLACK_WEBHOOK_VERSION}/gotify-slack-webhook-linux-${TARGETARCH}.so" \
 && case "$TARGETARCH" in \
      amd64) SHA="$GOTIFY_SLACK_WEBHOOK_SHA256_AMD64" ;; \
      arm64) SHA="$GOTIFY_SLACK_WEBHOOK_SHA256_ARM64" ;; \
      *) echo "Unsupported arch $TARGETARCH"; exit 1 ;; \
    esac \
 && echo "${SHA}  gotify-slack-webhook.so" | sha256sum -c -

# Build Gotify
FROM ghcr.io/gotify/server:2.7.3@sha256:2ae0e4e689f183137c8247884382fcb174d5a72253ce1897e7e5267090093fc8

ARG PLUGIN_DIR=/plugins

LABEL org.opencontainers.image.description="Gotify image with plugins"

COPY --from=downloader /downloads "$PLUGIN_DIR"
