FROM python:3.13.0@sha256:a31cbb4db18c6f09e3300fa85b77f6d56702501fcb9bdb8792ec702a39ba6200

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
