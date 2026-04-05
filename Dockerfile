FROM ghcr.io/astral-sh/uv:python3.13-trixie-slim

ENV HOME=/root \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY .python-version pyproject.toml README.md uv.lock ./

RUN uv sync --locked --no-dev

COPY gmail_genie.py ./

ENTRYPOINT ["uv", "run", "--locked", "--no-sync", "gmail_genie.py"]
CMD ["run", "--once"]
