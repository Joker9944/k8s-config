FROM python:3.13.2@sha256:8c55c44b9e81d537f8404d0000b7331863d134db87c1385dd0ec7fefff656495

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
