FROM python:3.14.2@sha256:2bf18f695b5d2077340609c72d3629946cb681b81bdc453b589d91a85a315138

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
