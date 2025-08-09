FROM python:3.13.6@sha256:68d0775234842868248bfe185eece56e725d3cb195f511a21233d0f564dee501

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
