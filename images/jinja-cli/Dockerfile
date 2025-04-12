FROM python:3.13.2@sha256:0293f851d58c726748c9f5d7dca65528ac2d38887b18a48e5689f6c59ef77ea9

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
