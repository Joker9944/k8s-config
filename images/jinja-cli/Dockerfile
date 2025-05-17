FROM python:3.13.3@sha256:653b0cf8fc50366277a21657209ddd54edd125499d20f3520c6b277eb8c828d3

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
