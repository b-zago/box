#!/bin/bash
set -euo pipefail

NAME=$1
USER=$2
PASSWORD=$(openssl rand -base64 32)

PARAM=$(jq -n --arg u "$USER" --arg p "$PASSWORD" '{username: $u, password: $p}')
aws ssm put-parameter --name "$NAME" --value "$PARAM" --type SecureString --overwrite
