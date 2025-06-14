FROM python:3.13.4@sha256:b077ca6a99f3e8f96d686bf4c590ed59079b779ef33090db3fb7cf348ba47c6d

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
