#!/bin/env bash
# Create the migrator and app credentials for a database in SSM.
# The migrator password is generated; the app password is supplied.
# Won't touch existing parameters unless --force is passed.
#
#   ./put-credentials.sh nyanify "$APP_PASSWORD"
#   ./put-credentials.sh nyanify "$APP_PASSWORD" --force   # rotate

set -euo pipefail

DB="${1:?usage: $0 <database> <app-password> <cluster> [--force]}"
APP_PASSWORD="${2:?usage: $0 <database> <app-password> [--force]}"
CLUSTER="${3:?usage: $0 <database> <app-password> <cluster> [--force]}"
FORCE="${4:-}"
PREFIX="${SSM_PREFIX:-/clusters/pgsql}"
REGION="${AWS_REGION:-eu-central-1}"

urlencode() {
  jq -rn --arg v "$1" '$v | @uri'
}

put() {
  local name="$1" user="$2" password="$3" genURL="$4"

  if aws ssm get-parameter --name "$name" --region "$REGION" >/dev/null 2>&1 &&
    [ "$FORCE" != "--force" ]; then
    echo "skip   $name (exists)"
    return
  fi

  local value host url

  host=$(aws ssm get-parameter --name "$PREFIX/host" --with-decryption \
    --region "$REGION" --query "Parameter.Value" --output text | jq -r '.host')

  if [[ "$genURL" == true ]]; then
    url="postgres://$(urlencode "$user"):$(urlencode "$password")@${host}:5432/${DB}?sslmode=disable"
    value=$(jq -nc --arg u "$user" --arg p "$password" --arg url "$url" \
      '{username:$u,password:$p,url:$url}')
  else
    value=$(jq -nc --arg u "$user" --arg p "$password" --arg h "$host" '{username:$u,password:$p,host:$h}')
  fi

  aws ssm put-parameter --name "$name" --value "$value" \
    --type SecureString --overwrite --region "$REGION" >/dev/null
  echo "wrote  $name ($user)"
}

put "$PREFIX/$CLUSTER/$DB/migrator" "${DB}_migrator" \
  "$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)" \
  true

put "$PREFIX/$CLUSTER/$DB/app" "${DB}_app" "$APP_PASSWORD" false
