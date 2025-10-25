FROM python:3.14.0@sha256:78ad0471881f0232093c9e6edf58addade7bf106377732e0790c0f0c914b3b7b

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
