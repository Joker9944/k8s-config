FROM python:3.13.3@sha256:0bc836167214f98aca9c9bca7b4c6dc2c2a77f4a29d5029e6561a14706335102

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
