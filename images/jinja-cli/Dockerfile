FROM python:3.12.6@sha256:79969aedd078863e55b32e908f3d94ac78ec9667e3b3b3b7070aeac27209382f

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
