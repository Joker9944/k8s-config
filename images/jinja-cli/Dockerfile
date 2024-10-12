FROM python:3.13.0@sha256:45803c375b95ea33f482e53a461eca8f247617667d703660a06ccf5eb3d05326

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
