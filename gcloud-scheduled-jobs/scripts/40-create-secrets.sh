#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

ensure_secret "$SECRET_GMAIL_CREDENTIALS_JSON"
ensure_secret "$SECRET_GMAIL_TOKEN_PICKLE"
ensure_secret "$SECRET_GMAIL_RULES_JSON"
