FROM python:3.13.1@sha256:cea505b81701dd9e46b8dde96eaa8054c4bd2035dbb660edeb7af947ed38a0ad

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
