#!/bin/bash
set -euo pipefail

SSM_PREFIX=$1
USER=$2
HOST=$3
PASSWORD=$(openssl rand -base64 32)

PARAM=$(jq -n --arg u "$USER" --arg p "$PASSWORD" '{username: $u, password: $p}')
aws ssm put-parameter --name "$SSM_PREFIX/admin" --value "$PARAM" --type SecureString --overwrite

PARAM=$(jq -n --arg h "$HOST" '{host: $h}')
aws ssm put-parameter --name "$SSM_PREFIX/host" --value "$PARAM" --type SecureString --overwrite
