FROM python:3.13.4@sha256:eb120d016adcbc8bac194e15826bbb4f1d1569d298d8817bb5049ed5e59f41d9

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
