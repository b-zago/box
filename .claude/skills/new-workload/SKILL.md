---
name: new-workload
description: Add a new application workload to this repo (box) on the generic helm-framework chart, across staging and prod. Use when adding an app, its in-cluster Redis, or a Postgres database for it, or when checking that an existing app follows the repo conventions.
---

# Adding a workload

Every workload is the generic chart `k3s/charts/app` (helm-framework 1.6.1, one
include). The ApplicationSet `k3s/overlays/<env>/workloads.yaml` creates one
Argo app per directory under `k3s/overlays/<env>/workloads/` and layers:

1. `k3s/overlays/<env>/workloads/values.yaml`: env defaults (pull secret, resources, probes, gateway, HPA bounds, Service sync-wave)
2. `k3s/base/workloads/<app>/values.yaml`: the app itself
3. `k3s/overlays/<env>/workloads/<app>/values.yaml`: tag, hostnames, env-specific secrets

For what a value does, use the `helm-framework:helm-framework` skill. This skill
covers only this repo's conventions. Copy from the real apps rather than from
memory:

| Kind | Example |
|---|---|
| Static site, no probes | `portfolio` |
| App with its own secret from SSM | `nyanify` |
| App + Redis + metrics | `ships`, `ships-redis` |
| App + Postgres + schema Job + Redis | `scorevault`, `scorevault-redis` |

## Ask first

App name (it becomes the directory, release and resource name), image
repository, container port, public or internal, hostnames per env, image tags
per env (staging `x.y.z-staging.N`, prod `x.y.z`; they must already exist in
ghcr), `/healthz` + `/ready` or not, metrics port, and whether it needs Redis
and/or Postgres.

## Files

**Always**, all three, even if one only holds a comment (`# Nothing staging-specific.`),
because the ApplicationSet references every layer:

- `k3s/base/workloads/<app>/values.yaml`
- `k3s/overlays/staging/workloads/<app>/values.yaml`
- `k3s/overlays/prod/workloads/<app>/values.yaml`

Rules for the values:

- `image.tag` lives only in the env files: CI bumps it there with `yq`.
- Public app: `httpRoute.enabled: true` with `paths: [{path: /}]` in base,
  `httpRoute.hostnames` in the env files. Staging hosts are
  `<app>.staging.zagoapps.com`, prod `<app>.zagoapps.com`. Don't set
  `parentRefs`: the env defaults do.
- `service.targetPort` is the container port. Don't rename the port: the Service
  always targets the named port `http`.
- No `/healthz` and `/ready`: set `healthChecks.enabled: false`.
- Metrics: add `service.extraPorts: [{name: metrics, port: <port>}]`. The shared
  ServiceMonitor `workloads` scrapes any port named `metrics` at `/metrics`.
  Never add a per-app ServiceMonitor.
- Scheduling: copy the `affinity` block from `scorevault` (stay off the control
  plane, spread across nodes) and change the `app.kubernetes.io/name` value.
  Redis apps only get the nodeAffinity part.
- HPA: `horizontalPodAutoscaler.enabled: true` for public apps. The bounds come
  from the env defaults.
- An app secret that only the app reads goes in the env file as
  `externalSecrets.<app>` with `extract.key: /clusters/<env>/<app>/app`
  (see `nyanify`). The user creates that SSM parameter.

**Redis** (`<app>-redis`): a separate workload, same three files. Copy
`scorevault-redis`: `redis:8-alpine`, port 6379, no probes, no route. The app
reaches it at host `<app>-redis`.

**Postgres**, on top of the above:

- The database name is `<app>-staging` in staging and `<app>` in prod.
- Add it to `k3s/overlays/<env>/config/databases.yaml`, one per line.
- Add the ExternalSecrets `<app>-db-app` and `<app>-db-migrator` to
  `k3s/overlays/<env>/config/workload-db-secrets.yaml`, copying the scorevault
  pair. SSM keys: `/clusters/pgsql/<env>/<db>/{app,migrator}`, and set
  `POSTGRES_DB` to `<db>`. They live in config-app, **not** in the chart: the
  schema Job is a PreSync hook, and on a fresh install it would wait forever
  for a Secret the same sync hasn't created yet. Secret names are
  env-independent, so base values can reference them.
- In base values, the app reads `<app>-db-app` through `envVars` `secretKeyRef`.
  The schema is a `jobs:` entry (`postgres:17-alpine`, `envFrom` the migrator
  secret, `psql "$url"`), as in `scorevault`. It runs before every sync, so it
  must be idempotent (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`,
  ...). Only the migrator creates objects; the app role gets DML via default
  privileges.

## Setting up the database (Postgres apps)

The user pushes and runs the commands. Give them these steps; don't run them
yourself. Do the whole sequence on staging first, then prod. `<db>` is
`<app>-staging` or `<app>`.

**1. Create the credentials in SSM** (locally, with AWS CLI credentials that
can write SSM, plus `jq` and `openssl`):

```sh
APP_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)
k3s/scripts/put-pgsql-creds.sh <db> "$APP_PASSWORD" <staging|prod>
```

- Arguments, in order: database name, app password, cluster (`staging`/`prod`,
  the SSM path segment). All three are required.
- It writes `/clusters/pgsql/<cluster>/<db>/migrator`
  (`{username,password,url}`, password generated) and `.../app`
  (`{username,password,host}`). Roles are `<db>_migrator` and `<db>_app`. The
  host comes from `/clusters/pgsql/host`.
- It skips parameters that already exist. A 4th argument `--force` overwrites
  both (rotation; see below).
- Optional env: `SSM_PREFIX` (default `/clusters/pgsql`), `AWS_REGION`
  (default `eu-central-1`).

**2. Push the config**: `<db>` added to `k3s/overlays/<env>/config/databases.yaml`
and the `<app>-db-*` ExternalSecrets added to `workload-db-secrets.yaml`. Then
wait until config-app is synced at that commit
(`status.sync.revision` = the pushed SHA). The bootstrap Job reads the
database list from that ConfigMap in the cluster, not from Git.

- Step 1 must come first. The bootstrap Job loops over **every** database in
  the list with `set -e`, so a database without SSM credentials breaks the
  bootstrap for all of them. The ExternalSecrets also need the parameters to
  exist.

**3. Create the database and roles** (kubectl pointed at that env's cluster,
e.g. `kcswitch staging-server.yaml`):

```sh
k3s/scripts/run-pgsql-db-bootstrap-job.sh          # Job manifest from main
k3s/scripts/run-pgsql-db-bootstrap-job.sh <ref>    # or from a branch/tag/SHA
```

- It deletes and re-applies `k3s/base/jobs/db-bootstrap/job.yaml` from GitHub
  at `<ref>`, follows the logs, and waits for completion. Expect `<db> ok` for
  every database.
- The Job runs in `postgresql-admin`. It gets AWS access from its service
  account (OIDC role in `pgsql-bootstrap-env`) and reads the admin credential
  from `/clusters/pgsql/admin`. Locally only kubectl is needed.
- It's idempotent: it creates any missing roles and the database (owned by
  the migrator), sets both passwords from SSM every run, and grants the app
  role DML on the migrator's future tables. Re-running it is safe.

**4. Push the workload values.** Argo runs the schema Job (PreSync) as the
migrator, then the app. Pushing this before steps 1–3 makes the schema Job
fail until they're done. If it already failed, re-running the sync after step
3 is enough.

In prod, the nightly `pgsql-backup` CronJob picks up every database in the
list, so the new database is backed up with no extra config.

**Rotating a password:** run `put-pgsql-creds.sh ... --force` (this regenerates
the migrator password too), then re-run the bootstrap Job. The ExternalSecrets
have `refreshInterval: 0s`, so they don't pick up the change by themselves:
force a refresh
(`kubectl annotate externalsecret <app>-db-app <app>-db-migrator -n <env> force-sync=$(date +%s) --overwrite`),
then restart the Deployment.

Apps without a database go out in one push. Do staging first, then prod.

## Outside this repo

Remind the user of what the skill can't do:

- The app repo's CI (`b-zago/actions` box-deployment) has to be set up to bump
  the tag.
- Any `/clusters/<env>/<app>/app` SSM parameter has to be created by hand.
- DNS, if the hostname isn't covered yet.

## Check before handing over

```sh
helm dependency build k3s/charts/app   # once
for env in staging prod; do
  helm template <app> k3s/charts/app --set nameOverride=<app> \
    -f k3s/overlays/$env/workloads/values.yaml \
    -f k3s/base/workloads/<app>/values.yaml \
    -f k3s/overlays/$env/workloads/<app>/values.yaml
done
```

Check: the names are `<app>`, the HTTPRoute has the right hosts and gateway,
the schema Job references existing Secret names, and any metrics port is named
`metrics`.
