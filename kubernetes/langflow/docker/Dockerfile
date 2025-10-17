ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends procps && rm -rf /var/lib/apt/lists/*

# ---- GUNICORN + UVICORN ok for venv or not venv base ----
# 1) venv: /app/.venv/bin/pip
# 2) no venv: pip / python3 -m pip
RUN set -eux; \
    if command -v /app/.venv/bin/pip >/dev/null 2>&1; then \
        /app/.venv/bin/pip install --no-cache-dir \
          "gunicorn>=21" "uvicorn[standard]>=0.30" "httptools" "uvloop"; \
    elif command -v pip >/dev/null 2>&1; then \
        pip install --no-cache-dir \
          "gunicorn>=21" "uvicorn[standard]>=0.30" "httptools" "uvloop"; \
    else \
        (python3 -m ensurepip || python -m ensurepip); \
        (python3 -m pip install --no-cache-dir \
          "gunicorn>=21" "uvicorn[standard]>=0.30" "httptools" "uvloop" \
         || python -m pip install --no-cache-dir \
          "gunicorn>=21" "uvicorn[standard]>=0.30" "httptools" "uvloop"); \
    fi

ENV PATH="/app/.venv/bin:${PATH}"

USER user
