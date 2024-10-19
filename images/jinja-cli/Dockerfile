FROM python:3.13.0@sha256:6cacef58b4bb19b78f2d00860d145d20ed1b1184125f5d405733b8d32f55d5ba

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
