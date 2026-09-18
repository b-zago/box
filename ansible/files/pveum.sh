#!/bin/bash
set -euo pipefail

USER=$1
DEFAULT_ROLE=$2
TOKEN_ID=$3

IS_USER=$(pveum user list --output-format json | jq -r '.[].userid' | grep "$USER" || true)
if [[ $IS_USER == "" ]]; then
  pveum user add "$USER" >&2
fi

IS_ROLE=$(pveum acl list --output-format json | jq -r --arg r "$DEFAULT_ROLE" '.[] | select(.roleid == $r) | .ugid' | grep "$USER" || true)
if [[ $IS_ROLE != "$USER" ]]; then
  pveum aclmod / -user "$USER" -role "$DEFAULT_ROLE" >&2
fi

IS_TOKEN=$(pveum user token list "$USER" --output-format json | jq -r --arg t "$TOKEN_ID" '.[] | select(.tokenid == $t) | .tokenid')
if [[ $IS_TOKEN == "" ]]; then
  pveum user token add "$USER" "$TOKEN_ID" --privsep=0 --output-format json | jq -r .value
fi
