#!/usr/bin/env bash
set -euo pipefail

TAILSCALED_PID=""
APP_PID=""
TAILSCALE_AUTHKEY_PATH="${TAILSCALE_AUTHKEY_PATH:-/var/run/secrets/tailscale/authkey}"
LLM_FEATURES_DISABLED=""
LLM_DISABLE_REASON=""

discover_tailnet_ip() {
  local peer_name="$1"

  [[ -n "$peer_name" ]] || return 1

  /usr/local/bin/tailscale status --json --peers | python3 -c '
import json
import sys

target = sys.argv[1].rstrip(".").casefold()
status = json.load(sys.stdin)

for peer in (status.get("Peer") or {}).values():
    host_name = str(peer.get("HostName", "")).rstrip(".").casefold()
    dns_name = str(peer.get("DNSName", "")).rstrip(".").casefold()
    candidates = {
        host_name,
        dns_name,
        host_name.split(".", 1)[0],
        dns_name.split(".", 1)[0],
    }
    candidates.discard("")

    if target not in candidates:
        continue

    if not peer.get("Online"):
        raise SystemExit(2)

    ips = peer.get("TailscaleIPs") or []
    for ip in ips:
        if ":" not in ip:
            print(ip)
            raise SystemExit(0)

    if ips:
        print(ips[0])
        raise SystemExit(0)

    raise SystemExit(3)

raise SystemExit(1)
' "$peer_name"
}

disable_llm_features() {
  local reason="$1"

  [[ -n "$reason" ]] || return 0
  if [[ -n "$LLM_FEATURES_DISABLED" ]]; then
    return 0
  fi

  LLM_FEATURES_DISABLED="1"
  LLM_DISABLE_REASON="$reason"
  unset TAILNET_LLM_API_IP
  unset LLM_ACTION_BASE_URL
  unset OPENAI_BASE_URL
  echo "Warning: ${reason}. Disabling LLM features for this run." >&2
}

discover_tailnet_hostnames() {
  local hostname_var ip_var peer_name discovered_ip attempt status
  local llm_hostname_var="TAILNET_LLM_API_HOSTNAME"

  while IFS='=' read -r hostname_var peer_name; do
    ip_var="${hostname_var%_HOSTNAME}_IP"

    discovered_ip=""
    status=1
    for attempt in 1 2 3 4 5; do
      if discovered_ip="$(discover_tailnet_ip "$peer_name" 2>/dev/null)"; then
        status=0
        break
      fi
      status=$?
      if [[ "$status" -eq 2 || "$status" -eq 3 ]]; then
        break
      fi
      if [[ "$attempt" -lt 5 ]]; then
        sleep 1
      fi
    done

    case "$status" in
      0)
        if [[ -n "${!ip_var:-}" ]]; then
          echo "Using preconfigured ${ip_var}=${!ip_var} from Tailscale peer ${peer_name} (online=true)"
        else
          export "$ip_var=$discovered_ip"
          echo "Discovered ${ip_var}=${discovered_ip} from Tailscale peer ${peer_name} (online=true)"
        fi
        ;;
      2)
        unset "$ip_var"
        echo "Warning: Tailscale peer ${peer_name} for ${ip_var} is offline (online=false); treating it as unreachable" >&2
        if [[ "$hostname_var" == "$llm_hostname_var" ]]; then
          disable_llm_features "Tailscale peer ${peer_name} for ${ip_var} is offline"
        fi
        ;;
      3)
        unset "$ip_var"
        echo "Warning: Tailscale peer ${peer_name} for ${ip_var} has no advertised Tailscale IP" >&2
        if [[ "$hostname_var" == "$llm_hostname_var" ]]; then
          disable_llm_features "Tailscale peer ${peer_name} for ${ip_var} has no advertised Tailscale IP"
        fi
        ;;
      *)
        unset "$ip_var"
        echo "Warning: could not resolve Tailscale peer ${peer_name} for ${ip_var}" >&2
        if [[ "$hostname_var" == "$llm_hostname_var" ]]; then
          disable_llm_features "Could not resolve Tailscale peer ${peer_name} for ${ip_var}"
        fi
        ;;
    esac
  done < <(env | grep '^TAILNET_.*_HOSTNAME=' || true)
}

prepare_app_args() {
  APP_ARGS=("$@")

  if [[ -z "$LLM_FEATURES_DISABLED" ]]; then
    return 0
  fi

  local arg
  local filtered_args=()
  local removed_enable_llm=""
  for arg in "${APP_ARGS[@]}"; do
    if [[ "$arg" == "--enable-llm" ]]; then
      removed_enable_llm="1"
      continue
    fi
    filtered_args+=("$arg")
  done
  APP_ARGS=("${filtered_args[@]}")

  if [[ -n "$removed_enable_llm" ]]; then
    echo "Warning: removed --enable-llm because ${LLM_DISABLE_REASON}" >&2
  fi
}

# shellcheck disable=SC2329
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

# shellcheck disable=SC2329
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
  discover_tailnet_hostnames
  
else
  echo "DEBUG: No Tailscale auth key file found at $TAILSCALE_AUTHKEY_PATH"
fi

trap cleanup EXIT
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

# If first arg is /bin/bash, run interactive shell with Tailscale running
if [ "${1:-}" = "/bin/bash" ]; then
  echo "Starting interactive shell (Tailscale running in background)"
  # Run bash in the foreground so it keeps the interactive TTY.
  /bin/bash -i
  exit "$?"
else
  prepare_app_args "$@"
  # Keep the wrapper shell alive so the EXIT trap can run cleanup.
  uv run --locked --no-sync gmail_genie.py "${APP_ARGS[@]}" &
fi
APP_PID=$!

if wait "$APP_PID"; then
  APP_STATUS=0
else
  APP_STATUS=$?
fi

exit "$APP_STATUS"
