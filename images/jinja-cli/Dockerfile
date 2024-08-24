FROM python:3.12.5@sha256:e3d5b6f95ce66923b5e48a06ee5755abb097de96a8617c3f2f7d431d48e63d35

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

ENTRYPOINT ["jinja2"]
