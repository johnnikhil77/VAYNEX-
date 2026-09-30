# Vaynex API image (Python 3.12, FastAPI, asyncpg).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

RUN useradd --create-home --uid 10001 vaynex

# Install dependencies first (cached layer). INSTALL_DEV=true also installs
# pytest so the test-suite can run inside the container.
ARG INSTALL_DEV=true
COPY pyproject.toml ./
RUN python -c "import os, tomllib; p = tomllib.load(open('pyproject.toml', 'rb'))['project']; deps = p['dependencies'] + (p['optional-dependencies']['dev'] if os.environ.get('INSTALL_DEV') == 'true' else []); open('/tmp/requirements.txt', 'w').write('\n'.join(deps))" \
    && pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY . .
RUN chown -R vaynex:vaynex /app
USER vaynex

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health', timeout=4).status == 200 else 1)"

# migrate -> optional seed -> uvicorn (see scripts/start.py)
CMD ["python", "scripts/start.py"]
