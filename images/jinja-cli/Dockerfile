FROM python:3.13.5@sha256:a6af772cf98267c48c145928cbeb35bd8e89b610acd70f93e3e8ac3e96c92af8

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
