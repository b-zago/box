#!/bin/bash
set -euo pipefail

SSM_PATH=$1
USER=$2
PASSWORD=$3

PARAM=$(jq -n --arg u "$USER" --arg p "$PASSWORD" '{username: $u, password: $p}')
aws ssm put-parameter --name "$SSM_PATH" --value "$PARAM" --type SecureString --overwrite
