FROM python:3.12.6@sha256:14f073695854184b65a82808ea2baa352d49c1a86442f06a90d9c236861c7a8f

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
