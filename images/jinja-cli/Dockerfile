FROM python:3.13.0@sha256:b740d32975a4c007dfc7a386444298ba9f443855635b71479bb8ce829682d931

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
