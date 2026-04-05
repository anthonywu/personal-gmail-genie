#!/usr/bin/env bash
set -euo pipefail

TAILSCALED_PID=""
APP_PID=""
TAILSCALE_AUTHKEY_PATH="${TAILSCALE_AUTHKEY_PATH:-/var/run/secrets/tailscale/authkey}"
TAILSCALE_SOCKS5_HOST="${TAILSCALE_SOCKS5_HOST:-127.0.0.1}"
TAILSCALE_SOCKS5_PORT="${TAILSCALE_SOCKS5_PORT:-1055}"
LLM_FEATURES_DISABLED=""
LLM_DISABLE_REASON=""

process_running() {
  local pid="$1"

  [[ -n "$pid" ]] || return 1
  ps -p "$pid" >/dev/null 2>&1
}

wait_for_tcp_listener() {
  local host="$1"
  local port="$2"
  local label="$3"
  local pid="${4:-}"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if nc -z "$host" "$port" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "$pid" ]] && ! process_running "$pid"; then
      echo "Warning: ${label} exited before ${host}:${port} became ready" >&2
      return 1
    fi
    sleep 1
  done

  echo "Warning: timed out waiting for ${label} at ${host}:${port}" >&2
  return 1
}

discover_tailnet_ip() {
  local peer_name="$1"
  local target="$1"

  [[ -n "$target" ]] || return 1

  target="${target%.}"
  target="${target,,}"

  /usr/local/bin/tailscale status --json --peers | jq -er --arg target "$target" '
    .Peer // {}
    | to_entries[]
    | .value as $peer
    | ($peer.HostName // "" | ascii_downcase | rtrimstr(".")) as $host
    | ($peer.DNSName // "" | ascii_downcase | rtrimstr(".")) as $dns
    | [
        $host,
        $dns,
        ($host | split(".")[0]),
        ($dns | split(".")[0])
      ] as $names
    | select($names | index($target))
    | [
        ($peer.Online // false),
        (
          (($peer.TailscaleIPs // []) | map(select(contains(":") | not)) | .[0])
          // (($peer.TailscaleIPs // [])[0])
          // ""
        )
      ]
    | @tsv
  ' | {
    local online
    local ip

    IFS=$'\t' read -r online ip || exit 1

    if [[ "$online" != "true" ]]; then
      exit 2
    fi
    if [[ -z "$ip" ]]; then
      exit 3
    fi

    printf '%s\n' "$ip"
  }
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

build_tailnet_llm_base_url() {
  local ip="$1"
  local scheme="${TAILNET_LLM_API_SCHEME:-http}"
  local port="${TAILNET_LLM_API_PORT:-11434}"
  local path="${TAILNET_LLM_API_PATH:-/v1}"

  [[ -n "$ip" ]] || return 1
  [[ -n "$path" ]] && [[ "$path" != /* ]] && path="/$path"

  if [[ -n "$port" ]]; then
    printf '%s://%s:%s%s\n' "$scheme" "$ip" "$port" "$path"
  else
    printf '%s://%s%s\n' "$scheme" "$ip" "$path"
  fi
}

configure_tailnet_llm_base_url() {
  local llm_ip="${TAILNET_LLM_API_IP:-}"
  local base_url

  [[ -n "$llm_ip" ]] || return 0
  if [[ -n "${LLM_ACTION_BASE_URL:-}" ]]; then
    echo "Using preconfigured LLM_ACTION_BASE_URL=${LLM_ACTION_BASE_URL}"
    return 0
  fi
  if [[ -n "${OPENAI_BASE_URL:-}" ]]; then
    echo "Using preconfigured OPENAI_BASE_URL=${OPENAI_BASE_URL}"
    return 0
  fi

  base_url="$(build_tailnet_llm_base_url "$llm_ip")"
  export LLM_ACTION_BASE_URL="$base_url"
  export OPENAI_BASE_URL="$base_url"
  echo "Derived LLM_ACTION_BASE_URL=${base_url} from TAILNET_LLM_API_IP=${llm_ip}"
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
    if wait_for_tcp_listener "$TAILSCALE_SOCKS5_HOST" "$TAILSCALE_SOCKS5_PORT" "tailscaled SOCKS5 listener" "$TAILSCALED_PID" >/dev/null 2>&1; then
      /usr/local/bin/tailscale logout >/dev/null 2>&1 || true
    fi
    if process_running "$TAILSCALED_PID"; then
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

  if process_running "$APP_PID"; then
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
  /usr/local/bin/tailscaled --tun=userspace-networking --socks5-server="${TAILSCALE_SOCKS5_HOST}:${TAILSCALE_SOCKS5_PORT}" 2>/dev/null &
  TAILSCALED_PID=$!
  echo "DEBUG: tailscaled PID=$TAILSCALED_PID"

  if ! wait_for_tcp_listener "$TAILSCALE_SOCKS5_HOST" "$TAILSCALE_SOCKS5_PORT" "tailscaled SOCKS5 listener" "$TAILSCALED_PID"; then
    ps -p "$TAILSCALED_PID" -o pid=,stat=,command= 2>/dev/null || true
    exit 1
  fi

  # Authenticate with Tailscale
  /usr/local/bin/tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname=gmail-genie-cloud-run
  unset TAILSCALE_AUTHKEY
  echo "Tailscale connected"
  discover_tailnet_hostnames
  configure_tailnet_llm_base_url
  
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
