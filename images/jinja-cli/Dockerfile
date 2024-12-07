FROM python:3.13.1@sha256:220d07595f288567bbf07883576f6591dad77d824dce74f0c73850e129fa1f46

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
