#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

sync_secret_file "$SECRET_GMAIL_CREDENTIALS_JSON" "$LOCAL_GMAIL_CREDENTIALS_JSON"
sync_secret_file "$SECRET_GMAIL_TOKEN_PICKLE" "$LOCAL_GMAIL_TOKEN_PICKLE"
sync_secret_file "$SECRET_GMAIL_RULES_JSON" "$LOCAL_GMAIL_RULES_JSON"
