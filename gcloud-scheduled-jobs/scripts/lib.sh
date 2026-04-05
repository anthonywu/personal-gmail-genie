#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OPS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${OPS_DIR}/.." && pwd)"
DEFAULT_ENV_FILE="${OPS_DIR}/.env.local"
LOADED_ENV_FILE="$DEFAULT_ENV_FILE"

export SCRIPT_DIR OPS_DIR REPO_ROOT DEFAULT_ENV_FILE

log() {
  printf '[gcloud-scheduled-jobs] %s\n' "$*"
}

die() {
  printf '[gcloud-scheduled-jobs] ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || die "Required file not found: $1"
}

load_env() {
  local env_file="${ENV_FILE:-${1:-$DEFAULT_ENV_FILE}}"

  [[ -f "$env_file" ]] || die "Missing env file: $env_file"
  LOADED_ENV_FILE="$env_file"

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  resolve_gcloud_bin
  derive_project_id
  validate_required_vars
  derive_defaults
}

resolve_gcloud_bin() {
  if [[ -n "${GCLOUD_BIN:-}" ]]; then
    :
  elif [[ -x "/Users/anthonywu/google-cloud-sdk/bin/gcloud" ]]; then
    GCLOUD_BIN="/Users/anthonywu/google-cloud-sdk/bin/gcloud"
  elif command -v gcloud >/dev/null 2>&1; then
    GCLOUD_BIN="$(command -v gcloud)"
  else
    die "gcloud not found; set GCLOUD_BIN in ${DEFAULT_ENV_FILE}"
  fi

  [[ -x "$GCLOUD_BIN" ]] || die "gcloud binary is not executable: $GCLOUD_BIN"
}

derive_project_id() {
  if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
    GCP_PROJECT_ID="$($GCLOUD_BIN config get-value project 2>/dev/null || true)"
  fi

  export GCLOUD_BIN GCP_PROJECT_ID
}

derive_defaults() {
  RUNTIME_SERVICE_ACCOUNT_EMAIL="${RUNTIME_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
  SCHEDULER_SERVICE_ACCOUNT_EMAIL="${SCHEDULER_SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
  IMAGE_URI="${GCP_ARTIFACT_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
  JOB_RUN_URI="https://run.googleapis.com/v2/projects/${GCP_PROJECT_ID}/locations/${GCP_REGION}/jobs/${CLOUD_RUN_JOB_NAME}:run"
  SECRET_MOUNTS="/var/run/gmail-genie/credentials/credentials.json=${SECRET_GMAIL_CREDENTIALS_JSON}:latest,/var/run/gmail-genie/token/token.pickle=${SECRET_GMAIL_TOKEN_PICKLE}:latest,/var/run/gmail-genie/rules/rules.json=${SECRET_GMAIL_RULES_JSON}:latest"
  STARTUP_COMMAND="mkdir -p /root/.config/gmail-genie && cp /var/run/gmail-genie/credentials/credentials.json /root/.config/gmail-genie/credentials.json && cp /var/run/gmail-genie/token/token.pickle /root/.config/gmail-genie/token.pickle && cp /var/run/gmail-genie/rules/rules.json /root/.config/gmail-genie/rules.json && exec uv run --locked --no-sync gmail_genie.py run --once"

  export RUNTIME_SERVICE_ACCOUNT_EMAIL SCHEDULER_SERVICE_ACCOUNT_EMAIL IMAGE_URI JOB_RUN_URI SECRET_MOUNTS STARTUP_COMMAND
}

validate_required_vars() {
  local required=(
    GCP_PROJECT_ID
    GCP_REGION
    GCP_ARTIFACT_REGION
    GCP_SCHEDULER_REGION
    AR_REPOSITORY
    IMAGE_NAME
    IMAGE_TAG
    CLOUD_RUN_JOB_NAME
    CLOUD_RUN_JOB_CPU
    CLOUD_RUN_JOB_MEMORY
    CLOUD_RUN_JOB_TASKS
    CLOUD_RUN_JOB_MAX_RETRIES
    CLOUD_RUN_JOB_TASK_TIMEOUT
    RUNTIME_SERVICE_ACCOUNT_ID
    SCHEDULER_SERVICE_ACCOUNT_ID
    SCHEDULER_JOB_NAME
    SCHEDULER_CRON
    SCHEDULER_TIME_ZONE
    SCHEDULER_OAUTH_TOKEN_SCOPE
    SECRET_GMAIL_CREDENTIALS_JSON
    SECRET_GMAIL_TOKEN_PICKLE
    SECRET_GMAIL_RULES_JSON
    LOCAL_GMAIL_CREDENTIALS_JSON
    LOCAL_GMAIL_TOKEN_PICKLE
    LOCAL_GMAIL_RULES_JSON
    LOG_LIMIT
  )
  local missing=()
  local name

  for name in "${required[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      missing+=("$name")
    fi
  done

  if ((${#missing[@]} > 0)); then
    die "Missing required env vars in ${LOADED_ENV_FILE}: ${missing[*]}"
  fi
}

gcloud() {
  "$GCLOUD_BIN" --project="$GCP_PROJECT_ID" "$@"
}

ensure_service_account() {
  local account_id="$1"
  local display_name="$2"
  local email="${account_id}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

  if gcloud iam service-accounts describe "$email" >/dev/null 2>&1; then
    log "Service account exists: $email"
    return
  fi

  log "Creating service account: $email"
  gcloud iam service-accounts create "$account_id" --display-name="$display_name" >/dev/null
}

ensure_secret() {
  local secret_name="$1"

  if gcloud secrets describe "$secret_name" >/dev/null 2>&1; then
    log "Secret exists: $secret_name"
    return
  fi

  log "Creating secret: $secret_name"
  gcloud secrets create "$secret_name" --replication-policy=automatic >/dev/null
}

secret_has_versions() {
  local secret_name="$1"

  [[ -n "$(gcloud secrets versions list --secret="$secret_name" --limit=1 --format='value(name)' 2>/dev/null)" ]]
}

sync_secret_file() {
  local secret_name="$1"
  local local_path="$2"
  local temp_file

  require_file "$local_path"

  if ! secret_has_versions "$secret_name"; then
    log "Uploading first version for secret: $secret_name"
    gcloud secrets versions add "$secret_name" --data-file="$local_path" >/dev/null
    return
  fi

  temp_file="$(mktemp)"
  gcloud secrets versions access latest --secret="$secret_name" >"$temp_file"

  if cmp -s "$temp_file" "$local_path"; then
    rm -f "$temp_file"
    log "Secret already matches local file: $secret_name"
    return
  fi

  rm -f "$temp_file"
  log "Uploading updated secret version: $secret_name"
  gcloud secrets versions add "$secret_name" --data-file="$local_path" >/dev/null
}

ensure_artifact_registry_repo() {
  if gcloud artifacts repositories describe "$AR_REPOSITORY" --location="$GCP_ARTIFACT_REGION" >/dev/null 2>&1; then
    log "Artifact Registry repository exists: $AR_REPOSITORY"
    return
  fi

  log "Creating Artifact Registry repository: $AR_REPOSITORY"
  gcloud artifacts repositories create "$AR_REPOSITORY" \
    --location="$GCP_ARTIFACT_REGION" \
    --repository-format=docker \
    --description="Container images for gmail-genie" >/dev/null
}

ensure_job_invoker_binding() {
  local member="serviceAccount:${SCHEDULER_SERVICE_ACCOUNT_EMAIL}"

  log "Granting Cloud Run job invoker to ${SCHEDULER_SERVICE_ACCOUNT_EMAIL}"
  gcloud run jobs add-iam-policy-binding "$CLOUD_RUN_JOB_NAME" \
    --region="$GCP_REGION" \
    --member="$member" \
    --role="roles/run.invoker" >/dev/null
}

job_exists() {
  gcloud run jobs describe "$CLOUD_RUN_JOB_NAME" --region="$GCP_REGION" >/dev/null 2>&1
}

scheduler_job_exists() {
  gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$GCP_SCHEDULER_REGION" >/dev/null 2>&1
}
