# box

Infrastructure as code for my self-hosted Kubernetes platform: from a plain Debian server to separate **staging** and **production** clusters running real applications, with every step automated. It runs on a Hetzner dedicated server; the host setup was developed and tested end to end on AWS EC2, so the platform isn't tied to one provider.

**Ansible** turns the server into a Proxmox hypervisor and installs Kubernetes. **Terraform** creates the virtual machines and the AWS identity setup. **Argo CD** deploys everything inside the clusters from this repository. Applications are deployed with [rikami-operator](https://github.com/b-zago/rikami-operator), a Kubernetes operator I wrote.

## Highlights

- **No static cloud credentials.** The clusters authenticate to AWS through OIDC federation, the self-hosted equivalent of IRSA on EKS. Secrets are pulled from AWS SSM with short-lived tokens, and no AWS keys exist anywhere in the clusters. See [how it works](#aws-access-without-static-credentials).
- **Reproducible from scratch.** Four commands take a bare server to two working clusters. Terraform generates the Ansible inventories from its own outputs, so IPs and versions are defined in one place.
- **GitOps.** Argo CD app-of-apps with automatic sync, pruning and self-healing. New environments are generated from a template overlay.
- **Automated releases.** Application repositories update image tags in this repo from their CI: the `staging` branch deploys to staging, `main` deploys to production.
- **Locked down automatically.** Ansible sets up WireGuard and the firewall on the host: SSH and the Proxmox UI are only reachable through the VPN, everything else is denied, and secrets in the repo are encrypted with Ansible Vault.

## Contents

- [Architecture](#architecture)
- [AWS access without static credentials](#aws-access-without-static-credentials)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Building a cluster](#building-a-cluster)
- [Ansible](#ansible)
- [Terraform](#terraform)
- [Kubernetes](#kubernetes)
- [Security](#security)
- [Trade-offs](#trade-offs)

## Architecture

| Layer          | Tooling                   | What it does                                                                                                                       |
| -------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Host           | Ansible                   | Installs Proxmox VE on Debian, builds LVM storage on a dedicated disk, configures TLS, NAT networking, WireGuard and the firewall. |
| VMs            | Terraform (`bpg/proxmox`) | Creates the k3s nodes and a PostgreSQL VM from a Debian cloud image.                                                               |
| Kubernetes     | Ansible                   | Installs k3s, configures the OIDC issuer, joins agents, bootstraps Argo CD.                                                        |
| Cloud identity | Terraform + Ansible       | Publishes OIDC discovery documents to S3 and creates IAM roles per cluster.                                                        |
| In-cluster     | Argo CD                   | Deploys the platform components and applications from `k3s/`.                                                                      |

**Clusters**

| Cluster | Server           | Agents            |
| ------- | ---------------- | ----------------- |
| staging | 1 × 2 vCPU, 4 GB | 2 × 2 vCPU, 4 GB  |
| prod    | 1 × 2 vCPU, 4 GB | 2 × 3 vCPU, 12 GB |

Both clusters share one PostgreSQL VM (2 vCPU, 4 GB) running outside Kubernetes.

**Platform components** (deployed by Argo CD in each cluster): Traefik as the Gateway API implementation, MetalLB, cert-manager (Let's Encrypt wildcard certificates via Cloudflare DNS-01), External Secrets Operator, Atlas Operator for schema migrations, kube-prometheus-stack, and rikami-operator.

## AWS access without static credentials

Pods in the clusters read secrets from AWS SSM without any AWS access keys stored anywhere. This is how AWS's own IRSA works on EKS, rebuilt for self-hosted k3s:

1. **k3s gets a public issuer.** The API server is configured with a service-account issuer URL pointing to an S3 bucket, so the tokens it signs for service accounts name that URL as their issuer.
2. **The issuer is published.** `bootstrap.yml` reads the cluster's OIDC discovery document and signing keys (JWKS) from the API server and uploads them to that S3 location, where AWS can fetch them.
3. **AWS trusts the cluster.** `terraform/aws/oidc` registers the issuer as an IAM OIDC provider and creates roles whose trust policy allows exactly one Kubernetes service account each (for example `external-secrets` in staging), with access limited to specific SSM paths.
4. **Pods exchange tokens.** External Secrets presents its service-account token to AWS STS and receives short-lived credentials for its role. Nothing long-lived is ever stored.

All of this runs as part of the cluster bootstrap. Adding a cluster adds its issuer and roles automatically.

## Repository layout

```
ansible/       Host, k3s and PostgreSQL playbooks; inventories per environment
  ca/          Scripts for my own certificate authority (internal TLS)
terraform/
  proxmox/     VMs for both clusters and PostgreSQL; generates Ansible inventories
  aws/oidc/    OIDC providers and IAM roles that let the clusters read AWS SSM
k3s/
  base/        Argo CD applications for platform components and workloads
  overlays/    Per-environment config (staging, prod) generated from _template
docker/        Image for the database bootstrap Job
```

## Prerequisites

**Tools:** Ansible (with the collections in `ansible/requirements.yml`), Terraform, the AWS CLI with credentials for the account below, and the Ansible Vault password in `~/.ansible/vault-pass`.

**Host:** a Debian server (bare metal such as a Hetzner dedicated server, or an EC2 instance) with an additional disk for VM storage, reachable over SSH. The disk is selected by `ebs_id`, a substring matched against `/dev/disk/by-id/`, so it works for an EBS volume or any physical disk. Your WireGuard client's public key goes into the vault.

**AWS:**

- an S3 bucket for the OIDC documents, which must be publicly readable because AWS IAM fetches them over HTTPS,
- an S3 location for the internal CA certificate (created with `ansible/ca/ca_make.sh`),
- SSM parameters: `/clusters/config` with shared settings such as the Cloudflare API token, and the PostgreSQL admin credential,
- an S3 backend for Terraform state (configured through a git-ignored `backend.hcl`).

**DNS:** a domain managed by Cloudflare, used for Let's Encrypt DNS-01 validation.

## Building a cluster

```sh
# 1. Turn the Debian server into a Proxmox host
ansible-playbook -i ansible/inventory/infra ansible/pve-host.yml

# 2. Create the VMs (also writes ansible/inventory/<env>/inventory.ini)
terraform -chdir=terraform/proxmox/main apply

# 3. Install PostgreSQL
ansible-playbook -i ansible/inventory/infra ansible/postgresql.yml

# 4. Install k3s and bootstrap the platform, per environment
ansible-playbook -i ansible/inventory/staging ansible/bootstrap.yml
ansible-playbook -i ansible/inventory/staging ansible/agents.yml
```

Step 4 does the rest on its own: it publishes the cluster's OIDC documents, adds the cluster's IAM roles and applies `terraform/aws/oidc`, trusts the internal CA, generates the environment's overlay from `k3s/overlays/_template`, installs Argo CD and hands the cluster over to GitOps.

## Ansible

| Playbook         | Purpose                                                                                                                                                                                                                                                                             |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pve-host.yml`   | Installs Proxmox VE on Debian (kernel, packages, repositories), builds the LVM thin pool on the storage disk, installs a TLS certificate from the internal CA, sets up the NAT bridge and port forwarding, WireGuard and ufw. Creates the API token Terraform uses. Safe to re-run. |
| `postgresql.yml` | Installs PostgreSQL from the PGDG repository, allows the cluster subnet, and creates the bootstrap admin role with credentials read from AWS SSM.                                                                                                                                   |
| `bootstrap.yml`  | Installs the k3s server with an S3-hosted OIDC issuer, publishes the discovery document and JWKS, applies the AWS IAM roles, generates the GitOps overlay, installs Argo CD and MetalLB.                                                                                            |
| `agents.yml`     | Joins any number of agent nodes to the cluster.                                                                                                                                                                                                                                     |

Inventories live in `ansible/inventory/{infra,staging,prod}`. Secrets are in `vault.yml` files encrypted with Ansible Vault. Collections are listed in `ansible/requirements.yml`.

## Terraform

| Root                     | Purpose                                                                                                                                                                       |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `terraform/proxmox/main` | Defines both clusters in one `clusters` map (versions, sizes, IPs) and creates every node through the reusable `modules/k3s-node-vm` module. Renders the Ansible inventories. |
| `terraform/proxmox/dev`  | A smaller single-cluster setup for testing, including the host's storage configuration.                                                                                       |
| `terraform/aws/oidc`     | For each cluster: an IAM OIDC provider and roles scoped to specific SSM paths, each trusted by one Kubernetes service account.                                                |

State and backend configuration are kept out of Git.

## Kubernetes

`k3s/overlays/<env>/root-app.yaml` is the single Argo CD application per cluster; everything else is reachable from it:

| Application | Contents                                                                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `infra`     | Helm-based platform components (see [Architecture](#architecture)).                                                                          |
| `config`    | Their environment-specific configuration: Gateways, ClusterIssuer, ClusterSecretStore, MetalLB pools, the rikami Profile, the database list. |
| `workloads` | Applications, each described as a rikami `Vessel`.                                                                                           |

**Databases.** Application databases are listed in a ConfigMap (`config/databases.yaml`), and their credentials are stored in AWS SSM with `k3s/scripts/put-pgsql-creds.sh`. A bootstrap Job reads the PostgreSQL admin credential and the application credentials directly from SSM and creates each database with its roles. External Secrets then delivers the application credentials to the app. The admin credential never becomes a Kubernetes Secret.

**Deployments.** Each application's CI pushes a commit that updates its image tag in the matching overlay. Argo CD rolls it out.

## Security

- **Network:** the VMs sit on a private bridge behind NAT. Only ports 80 and 443 are forwarded to the cluster ingress. SSH and the Proxmox UI are reachable only through WireGuard, and ufw denies all other incoming traffic.
- **Secrets:** stored in AWS SSM, read by External Secrets with per-cluster IAM roles. Repository secrets are encrypted with Ansible Vault. Terraform state, variables and keys are git-ignored.
- **TLS:** public endpoints use Let's Encrypt wildcard certificates. Internal services (Proxmox, Argo CD) use certificates from my own CA, which the nodes trust.

## Trade-offs

Deliberate choices for a single-person homelab, and what I would change in production:

- **One physical host.** All VMs run on one Proxmox server, so it's a single point of failure. Running three k3s servers with embedded etcd would add complexity without real high availability; that needs multiple physical hosts.
- **One k3s server per cluster.** Follows from the above. `agents.yml` adds as many workers as needed.
- **Shared PostgreSQL.** Both environments use one instance and one admin role to save resources, so staging isn't fully isolated from production data. In production I'd use separate instances, or at least per-environment admin roles.
- **The bootstrap commits to Git.** Generating an environment's overlay and the IAM role list during bootstrap and pushing them keeps Git the source of truth for Argo CD and Terraform, at the cost of an automated commit during setup.
