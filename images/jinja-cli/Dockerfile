FROM python:3.14.0@sha256:e3a6ccbe44d9cbfa4f107f238a0e95fa70e0d084e87689222e951d062ac89854

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
