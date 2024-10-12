FROM python:3.12.7@sha256:05855f5bf06f5a004b0c1a8aaac73a9d9ea54390fc289d3e80ef52c4f90d5585

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
