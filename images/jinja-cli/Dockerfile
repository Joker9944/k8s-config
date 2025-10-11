FROM python:3.13.7@sha256:fe841081ec55481496a4ab25e538833741295d57d2abdec8d38d74d65fb4715b

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
