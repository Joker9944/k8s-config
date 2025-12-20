FROM python:3.14.2@sha256:492b292a9449d096aefe5b1399cc64de53359845754da3e4d2539402013c826b

LABEL org.opencontainers.image.description="Python image with jinja2-cli installed"

COPY requirements.txt ./
RUN \
	pip install --no-cache-dir -r requirements.txt && \
	rm requirements.txt

USER nobody:nogroup

ENTRYPOINT ["jinja2"]
