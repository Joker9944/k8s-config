FROM python:3.13.5@sha256:28f60ab75da2183870846130cead1f6af30162148d3238348f78f89cf6160b5d

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
