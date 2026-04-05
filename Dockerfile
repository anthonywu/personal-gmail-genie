FROM ghcr.io/astral-sh/uv:python3.13-trixie-slim

ENV HOME=/root \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY .python-version pyproject.toml README.md uv.lock ./

RUN uv sync --locked --no-dev

# Install Tailscale binaries for optional Cloud Run VPN support
COPY --from=docker.io/tailscale/tailscale:stable /usr/local/bin/tailscaled /usr/local/bin/tailscale /usr/local/bin/

RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

COPY gmail_genie.py ./
COPY gcloud-scheduled-jobs/start.sh ./

RUN chmod +x ./start.sh

ENTRYPOINT ["./start.sh"]
