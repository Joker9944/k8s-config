FROM python:3.13.0@sha256:c590a3669258c6b416f05e4d0ec54197ada40829ee213b1722c545614ea2427a

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
