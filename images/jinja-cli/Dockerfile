FROM python:3.13.2@sha256:bc336add24c507d3a11b68a08fe694877faae3eab2d0e18b0653097f1a0db9f3

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
