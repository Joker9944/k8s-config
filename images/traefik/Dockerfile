FROM python:3.12.5@sha256:e3d5b6f95ce66923b5e48a06ee5755abb097de96a8617c3f2f7d431d48e63d35 AS builder

ARG PLUGIN_THEME_PARK_METHOD=https
ARG PLUGIN_THEME_PARK_REPO=github.com/packruler/traefik-themepark
ARG PLUGIN_THEME_PARK_VERSION=v1.4.0

ARG PLUGIN_GEOBLOCK_METHOD=https
ARG PLUGIN_GEOBLOCK_REPO=github.com/PascalMinder/geoblock
ARG PLUGIN_GEOBLOCK_VERSION=v0.2.8

ARG PLUGIN_REALIP_METHOD=https
ARG PLUGIN_REALIP_REPO=github.com/jramsgz/traefik-real-ip
ARG PLUGIN_REALIP_VERSION=v1.0.6

ARG PLUGIN_MODSECURITY_METHOD=https
ARG PLUGIN_MODSECURITY_REPO=github.com/acouvreur/traefik-modsecurity-plugin
ARG PLUGIN_MODSECURITY_VERSION=v1.3.0

ARG PLUGIN_CROWDSEC_BOUNCER_METHOD=https
ARG PLUGIN_CROWDSEC_BOUNCER_REPO=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
ARG PLUGIN_CROWDSEC_BOUNCER_VERSION=v1.3.0

ARG PLUGIN_REWRITERESPONSEHEADERS_METHOD=https
ARG PLUGIN_REWRITERESPONSEHEADERS_REPO=github.com/XciD/traefik-plugin-rewrite-headers
ARG PLUGIN_REWRITERESPONSEHEADERS_VERSION=v0.0.4

COPY requirements.txt ./
COPY install_plugins.py ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	python ./install_plugins.py

FROM traefik:v3.1.2@sha256:ec1a82940b8e00eaeef33fb4113aa1d1573b2ebb6440e10c023743fe96f08475

LABEL org.opencontainers.image.description="Default traefik image with local plugins installed"

COPY --from=builder /plugins-local /plugins-local
