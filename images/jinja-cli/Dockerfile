FROM python:3.13.2@sha256:589ed6659c0e4aac182f309131cd35e85452d21072570b1f6abc45b7687093a3

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
