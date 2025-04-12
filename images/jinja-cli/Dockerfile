FROM python:3.13.3@sha256:9819e5616923079cc16af4a93d4be92c0c487c6e02fd9027220381f3e125d64a

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
