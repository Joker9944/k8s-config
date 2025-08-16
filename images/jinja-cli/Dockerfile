FROM python:3.13.7@sha256:3b2f1b9c9948e9dc96e1a2f4668ba9870ff43ab834f91155697476142b3bc299

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
