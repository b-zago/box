#!/bin/bash

cp -r ../../k3s/overlays/_template/ "../../k3s/overlays/$ENV" && cd "../../k3s/overlays/$ENV"

for f in "../../k3s/overlays/$ENV"; do
  envsubst <"$f" >"$f.tmp" && mv "$f.tmp" "$f"
done
