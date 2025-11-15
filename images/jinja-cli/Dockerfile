FROM python:3.14.0@sha256:e6b1f7011589cc717a5112e6fdb56217e9e734a57e4cb50216e912b068b392a8

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
