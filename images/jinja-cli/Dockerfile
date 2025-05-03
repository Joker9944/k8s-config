FROM python:3.13.3@sha256:884da97271696864c2eca77c6362b1c501196d6377115c81bb9dd8d538033ec3

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
