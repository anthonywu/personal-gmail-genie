#!/usr/bin/env bash
set -euo pipefail

TAILSCALED_PID=""
APP_PID=""
TAILSCALE_AUTHKEY_PATH="${TAILSCALE_AUTHKEY_PATH:-/var/run/secrets/tailscale/authkey}"

# Cleanup function
cleanup() {
  if [ -n "$TAILSCALED_PID" ]; then
    echo "Cleaning up Tailscale..."
    # Give tailscale socket time to be ready
    sleep 1
    /usr/local/bin/tailscale logout >/dev/null 2>&1 || true
    sleep 1
    if [ -n "$TAILSCALED_PID" ] && kill -0 "$TAILSCALED_PID" 2>/dev/null; then
      kill "$TAILSCALED_PID" 2>/dev/null || true
      wait "$TAILSCALED_PID" 2>/dev/null || true
    fi
    echo "Tailscale cleanup complete"
  fi
}

forward_signal() {
  local signal="$1"
  local exit_code="143"

  if [ "$signal" = "INT" ]; then
    exit_code="130"
  fi

  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "-$signal" "$APP_PID" 2>/dev/null || kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi

  exit "$exit_code"
}

# Start Tailscale if auth key is provided
TAILSCALE_AUTHKEY=""
if [ -r "$TAILSCALE_AUTHKEY_PATH" ]; then
  IFS= read -r TAILSCALE_AUTHKEY < "$TAILSCALE_AUTHKEY_PATH" || true
fi

if [ -n "$TAILSCALE_AUTHKEY" ]; then
  echo "DEBUG: Starting Tailscale with auth key file: $TAILSCALE_AUTHKEY_PATH"
  echo "Starting Tailscale in userspace networking mode..."
  /usr/local/bin/tailscaled --tun=userspace-networking --socks5-server=localhost:1055 2>/dev/null &
  TAILSCALED_PID=$!
  echo "DEBUG: tailscaled PID=$TAILSCALED_PID"
  
  # Wait for socket to be ready
  sleep 2
  
  # Authenticate with Tailscale
  /usr/local/bin/tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname=gmail-genie-cloud-run
  unset TAILSCALE_AUTHKEY
  echo "Tailscale connected"
  
else
  echo "DEBUG: No Tailscale auth key file found at $TAILSCALE_AUTHKEY_PATH"
fi

trap cleanup EXIT
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

# If first arg is /bin/bash, run interactive shell with Tailscale running
if [ "${1:-}" = "/bin/bash" ]; then
  echo "Starting interactive shell (Tailscale running in background)"
  # Run bash as child process so cleanup still runs after bash exits.
  /bin/bash &
else
  # Keep the wrapper shell alive so the EXIT trap can run cleanup.
  uv run --locked --no-sync gmail_genie.py "$@" &
fi
APP_PID=$!

if wait "$APP_PID"; then
  APP_STATUS=0
else
  APP_STATUS=$?
fi

exit "$APP_STATUS"
