#!/bin/bash
set -e

rm -rf "../k3s/overlays/$ENV"
cp -r ../k3s/overlays/_template/ "../k3s/overlays/$ENV"

find "../k3s/overlays/$ENV" -type f -print0 | while IFS= read -r -d '' f; do
  envsubst <"$f" >"$f.tmp" && mv "$f.tmp" "$f"
done
