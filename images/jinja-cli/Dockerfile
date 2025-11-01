FROM python:3.14.0@sha256:934873f1360893d07afe0d25b99af46640e916a5900f1677fb86e41f73920253

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
