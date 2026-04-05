#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

log_filter="resource.type=cloud_run_job AND labels.\"run.googleapis.com/job_name\"=\"${CLOUD_RUN_JOB_NAME}\""

log "Showing the latest ${LOG_LIMIT} log entries for ${CLOUD_RUN_JOB_NAME}"
gcloud logging read "$log_filter" \
  --limit="$LOG_LIMIT" \
  --order=desc \
  --format="table(timestamp,severity,labels.\"run.googleapis.com/execution_name\",textPayload,jsonPayload.message)"
