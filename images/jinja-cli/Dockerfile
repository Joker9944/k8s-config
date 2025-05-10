FROM python:3.13.3@sha256:3abe339a3bc81ffabcecf9393445594124de6420b3cfddf248c52b1115218f04

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
