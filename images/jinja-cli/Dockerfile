FROM python:3.12.5@sha256:11aa4b620c15f855f66f02a7f3c1cd9cf843cc10f3edbcf158e5ebcd98d1f549

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
