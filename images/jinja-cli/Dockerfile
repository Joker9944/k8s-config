FROM python:3.12.7@sha256:785fef11f44b7393c03d77032fd72e56af8b05442b051a151229145e5fbbcb29

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
