# Zero Trust Gateway

A production-ready reference architecture that exposes a FastAPI application to the internet **without a public IP address**, using Cloudflare Tunnel for inbound traffic and Azure Key Vault (Private Endpoint) for secrets.

---

## Architecture

```
 Internet User
      │
      │ HTTPS (authenticated via Cloudflare Access — optional)
      ▼
┌─────────────────────────────────────────────────────┐
│              Cloudflare Edge Network                 │
│                                                      │
│   ┌──────────────────────┐                           │
│   │  Cloudflare Access   │  ← email OTP / SSO        │
│   │  (enable_access_app) │    (optional, off by default) │
│   └──────────┬───────────┘                           │
└──────────────┼──────────────────────────────────────┘
               │  Cloudflare Tunnel  (outbound TLS from VM)
               │  No inbound firewall holes required
               │
┌──────────────▼──────────────────────────────────────────────────────┐
│  Azure Virtual Network  10.0.0.0/16                                  │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  vm-subnet  10.0.1.0/24        NSG: deny-all-inbound         │   │
│  │                                                               │   │
│  │  ┌────────────────────────────────────────────────────────┐  │   │
│  │  │  Ubuntu 22.04 VM  (Standard_B1s)  — NO public IP       │  │   │
│  │  │                                                         │  │   │
│  │  │   ┌──────────────────┐   ┌──────────────────────────┐  │  │   │
│  │  │   │  cloudflared     │   │  FastAPI + uvicorn        │  │   │  │
│  │  │   │  (tunnel agent)  ├──►│  127.0.0.1:8000          │  │   │  │
│  │  │   └──────────────────┘   └────────────┬─────────────┘  │  │   │
│  │  │                                        │                │  │   │
│  │  │   Managed Identity (UAMI)              │ HTTPS + bearer │  │   │
│  │  └────────────────────────────────────────┼────────────────┘  │   │
│  └───────────────────────────────────────────┼────────────────────┘   │
│                                              │                         │
│  ┌───────────────────────────────────────────▼──────────────────┐    │
│  │  pe-subnet  10.0.2.0/24                                       │    │
│  │                                                               │    │
│  │  Azure Key Vault  (Private Endpoint)                          │    │
│  │  kv-ztgw-demo.vault.azure.net → 10.0.2.x  (private DNS)     │    │
│  │                                                               │    │
│  │  Secrets: SNOWFLAKE-ACCOUNT, SNOWFLAKE-USER,                 │    │
│  │           SNOWFLAKE-PASSWORD, CLOUDFLARE-TUNNEL-TOKEN,       │    │
│  │           SSH-PRIVATE-KEY                                     │    │
│  └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
               │
               │ HTTPS outbound  (Snowflake network policy allows VM egress IP)
               ▼
      ┌──────────────────┐
      │    Snowflake     │
      │  (GATEWAY_SVC)   │
      │  DEMO_DB /       │
      │  INFRASTRUCTURE_ │
      │  METRICS table   │
      └──────────────────┘

Boot sequence (cloud-init, runs once on first VM boot):
  1. Installs packages: python3.11, cloudflared, ufw, jq, curl
  2. Configures UFW: deny-all inbound, allow-all outbound
  3. Writes FastAPI app + systemd units to disk
  4. Creates Python venv, pip install dependencies
  5. bootstrap-cloudflared.sh:
       IMDS → Managed Identity token → Key Vault → CLOUDFLARE-TUNNEL-TOKEN
       writes /etc/cloudflared/env (mode 600)
  6. systemctl start fastapi-gateway cloudflared
  → Tunnel goes healthy ~5-8 min after terraform apply
```

---

## VM vs Container App

| Dimension | **This project — Azure VM** | Alternative — Azure Container App |
|---|---|---|
| **Image management** | None — cloud-init provisions everything at boot | Docker image must be built and pushed to ACR before apply |
| **Startup time** | ~5-8 min (cloud-init + pip install) | ~2-3 min (image pull) |
| **Cold start** | Always-on VM, no cold start | Can scale to zero (cold start on first request) |
| **Secrets access** | Key Vault Private Endpoint (no public KV exposure) | Key Vault references or environment injection |
| **Zero Trust integration** | cloudflared runs on the same VM as FastAPI | Sidecar container or external tunnel |
| **Cost (idle)** | ~$7-15/month (Standard_B1s) | ~$0-3/month (scale-to-zero) |
| **Bastion SSH** | Optional (`deploy_bastion=true`) | `az containerapp exec` |
| **Windows dev experience** | CRLF-safe: files are base64-encoded in cloud-init | No CRLF concerns |
| **Best for** | Demos, long-running workloads, no container registry setup | Microservices, auto-scaling, production-grade deployments |

---

## Prerequisites

| Tool | Min version | Install |
|---|---|---|
| Terraform | 1.5+ | [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads) |
| Azure CLI (`az`) | 2.50+ | [docs.microsoft.com/en-us/cli/azure/install-azure-cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Python 3 | 3.8+ | (for `make test-*` JSON pretty-printing) |
| Azure subscription | — | [portal.azure.com](https://portal.azure.com) |
| Cloudflare account | Free+ | [cloudflare.com](https://cloudflare.com) — no custom domain required |
| Snowflake account | Any edition | [snowflake.com](https://snowflake.com) |

---

## Quick Start (6 commands)

```bash
# 1. Clone and enter the project
git clone <repo-url> zero-trust-gateway2 && cd zero-trust-gateway2

# 2. Copy and fill in secrets
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
#    Edit terraform.tfvars — fill in Cloudflare, Snowflake, and Azure values

# 3. Run pre-flight checks (verifies CLI tools, Azure login, terraform init)
./scripts/bootstrap.sh

# 4. Deploy everything (VM + Key Vault + Cloudflare tunnel + Snowflake)
make apply
#    Takes ~3 min. Note the tunnel_url in the output.

# 5. Wait for cloud-init to finish (~5 min after apply)
#    Poll until both services are active:
make vm-status

# 6. Test the live endpoint
make test-health
```

---

## Configuration (terraform/terraform.tfvars)

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in values.

**`terraform.tfvars` is gitignored** — never commit it. Use `.env` with `TF_VAR_*` exports for team sharing.

### Required values

| Variable | Description |
|---|---|
| `key_vault_name` | Globally unique Key Vault name (3-24 chars, alphanumeric + hyphens) |
| `snowflake_account` | Your Snowflake account identifier (e.g. `xy12345.us-east-1`) |
| `snowflake_admin_user` | Snowflake admin user (SYSADMIN or ACCOUNTADMIN) |
| `snowflake_admin_password` | Snowflake admin password |
| `snowflake_svc_password` | Password for the `GATEWAY_SVC` service account created by Terraform |
| `cloudflare_api_token` | Cloudflare API token with Tunnel + DNS + Access scopes |
| `cloudflare_account_id` | Your Cloudflare Account ID |
| `allowed_email` | Email allowed through Cloudflare Access (if enabled) |

### Optional values

| Variable | Default | Description |
|---|---|---|
| `cloudflare_zone_id` | `""` | Cloudflare Zone ID — only needed for custom domain |
| `tunnel_hostname` | `""` | Custom hostname (e.g. `gateway.yourdomain.com`) — omit to use `<id>.cfargotunnel.com` |
| `enable_access_app` | `false` | Enable Cloudflare Access authentication in front of the tunnel |
| `enable_gateway_egress` | `false` | Use Cloudflare Gateway dedicated egress IP in Snowflake network policy |
| `deploy_bastion` | `false` | Deploy Azure Bastion for SSH access (~$5/day extra) |
| `location` | — | Azure region (e.g. `eastus`) |
| `resource_group_name` | — | Azure Resource Group name |

---

## How cloud-init Works

`cloud-init.yaml.tpl` is processed by Terraform's `templatefile()` function when you run `terraform apply`. Terraform base64-encodes all Python app files and systemd units, then embeds them in the YAML.

When the VM boots for the first time, cloud-init runs the YAML sequentially:

```
Phase 1 — write_files  (write all files to disk)
  /etc/environment           ← KEY_VAULT_URL, AZURE_CLIENT_ID
  /opt/gateway/main.py       ← FastAPI app (base64-encoded)
  /opt/gateway/routers/      ← health.py, data.py
  /opt/gateway/services/     ← keyvault_client.py, snowflake_client.py
  /opt/gateway/pyproject.toml
  /etc/systemd/system/fastapi-gateway.service  (base64-encoded)
  /etc/systemd/system/cloudflared.service      (base64-encoded)
  /usr/local/bin/bootstrap-cloudflared.sh      (base64-encoded)

Phase 2 — runcmd  (sequential shell commands as root)
  ufw default deny incoming / allow outgoing / enable
  apt-get install cloudflared
  chown -R gateway:gateway /opt/gateway
  python3.11 -m venv /opt/gateway/.venv && pip install deps
  sed -i 's/\r//' <service files>   ← strips Windows CRLF
  /usr/local/bin/bootstrap-cloudflared.sh
  systemctl enable + start fastapi-gateway cloudflared
```

**Why base64-encoded files?** The cloudflared systemd unit contains `${TUNNEL_TOKEN}` shell variable syntax. Without base64 encoding, Terraform's template engine would try to substitute it, causing a parse error.

**Why no `owner:` in write_files?** cloud-init's `write_files` phase runs before the `users` phase creates the `gateway` system account. Setting `owner: gateway:gateway` in write_files causes an `OSError: Unknown user`. The `chown` in `runcmd` handles ownership after the user exists.

---

## Tunnel Token Bootstrap

The VM has no SSH access and no public IP at boot time. Getting the Cloudflare tunnel token onto the VM requires:

```
  terraform apply
       │
       ├─ Creates Cloudflare tunnel → gets tunnel token
       ├─ Stores token in Key Vault as secret "CLOUDFLARE-TUNNEL-TOKEN"
       └─ Provisions VM with Managed Identity attached
              │
              │  (VM boots, cloud-init runs)
              ▼
  bootstrap-cloudflared.sh
       │
       ├─ 1. Reads KEY_VAULT_URL from /etc/environment
       ├─ 2. Polls IMDS (169.254.169.254) until Managed Identity ready
       ├─ 3. Requests Key Vault access token from IMDS
       ├─ 4. Fetches CLOUDFLARE-TUNNEL-TOKEN secret via Key Vault REST API
       ├─ 5. Writes TUNNEL_TOKEN=<value> to /etc/cloudflared/env (chmod 600)
       └─ 6. cloudflared service reads /etc/cloudflared/env → tunnel connects
```

This is the **zero-trust bootstrap problem**: the VM needs a secret to connect, but you can't put the secret on the VM at build time. Managed Identity + Key Vault solves this with no long-lived credentials anywhere.

Logs are written to `/var/log/bootstrap-cloudflared.log` on the VM.

---

## Private Endpoint

The Azure Key Vault is accessed via a **Private Endpoint** in `pe-subnet (10.0.2.0/24)`. This means:

- The Key Vault's DNS name (`kv-name.vault.azure.net`) resolves to a **private IP** (`10.0.2.x`) inside the VNet
- A Private DNS Zone (`privatelink.vaultcore.azure.net`) handles this resolution
- Traffic from the VM to Key Vault **never leaves the VNet** — no public internet transit
- `public_network_access_enabled = true` is set on the Key Vault so Terraform can write secrets during `apply` (from your workstation); the Private Endpoint is the primary access path from the VM

```
VM (10.0.1.x)
  └─ DNS: kv-ztgw-demo.vault.azure.net
            └─ Resolves via Private DNS Zone: 10.0.2.5  (pe-subnet)
                  └─ Private Endpoint NIC → Key Vault
                        No public internet used
```

---

## NSG Rules

The Network Security Group applied to `vm-subnet (10.0.1.0/24)`:

| Priority | Direction | Access | Protocol | Source | Destination | Port | Purpose |
|---|---|---|---|---|---|---|---|
| 100 | Outbound | Allow | TCP | VirtualNetwork | Internet | 443 | cloudflared tunnel + Snowflake HTTPS |
| 110 | Outbound | Allow | TCP | 10.0.1.0/24 | 10.0.2.0/24 | 443 | VM → Key Vault Private Endpoint |
| 120 | Outbound | Allow | TCP | 10.0.1.0/24 | 169.254.169.254/32 | 80 | IMDS (Managed Identity token fetch) |
| 4096 | Inbound | Deny | \* | Internet | \* | \* | Defence-in-depth (VM has no public IP anyway) |

The VM **cannot receive any inbound connections from the internet**. The Cloudflare Tunnel is outbound-only — cloudflared dials out to Cloudflare's edge, establishing an encrypted QUIC/HTTP2 connection. Cloudflare proxies requests back through that connection.

---

## SSH Key Retrieval

SSH access is disabled by default (no public IP, no NSG inbound rule). To enable SSH:

1. Set `deploy_bastion = true` in `terraform.tfvars` and run `terraform apply` (adds Azure Bastion ~$5/day)
2. Retrieve the SSH key from Key Vault:

```bash
make ssh-key
# Downloads SSH-PRIVATE-KEY secret → ~/.ssh/zt-vm-demo.pem

make ssh
# SSH to VM via Azure Bastion (no public IP needed)
```

**Without Bastion**, use Azure Portal → VM → Run command to execute shell commands on the VM:

```bash
# Check cloud-init logs
az vm run-command invoke \
  --resource-group rg-zero-trust-gateway2 \
  --name vm-zero-trust-gateway \
  --command-id RunShellScript \
  --scripts "tail -50 /var/log/cloud-init-output.log"

# Or use make:
make logs        # last 60 journald lines
make vm-status   # systemctl status + bootstrap log tail
```

---

## Teardown

```bash
# Destroy all infrastructure (VM, Key Vault, VNet, Cloudflare tunnel, Snowflake objects)
make destroy

# Or with confirmation prompt:
./scripts/destroy.sh
```

This destroys:
- Azure VM + OS disk
- Azure Key Vault (purged — no 7-day soft-delete retention because `purge_soft_delete_on_destroy = true`)
- Azure VNet + subnets + NSG
- Azure Private Endpoint + Private DNS Zone
- Azure User-Assigned Managed Identity
- Azure Log Analytics Workspace + data
- Cloudflare Tunnel + Access Application (if enabled)
- Snowflake database, schema, table, service account, role, network policy

---

## Cost Estimate

| Resource | SKU | Estimated monthly cost |
|---|---|---|
| Azure VM | Standard_B1s (1 vCPU, 1 GB RAM) | ~$7-8/month |
| Azure Key Vault | Standard tier | ~$0 (first 10k ops free) |
| Azure Private Endpoint | — | ~$7/month |
| Azure Log Analytics | PerGB2018, 30-day retention | ~$0-2/month (low volume) |
| Azure VNet + NSG | — | $0 |
| Azure Bastion | Basic SKU (optional) | ~$140/month if enabled |
| Cloudflare Tunnel | Free | $0 |
| Snowflake | T-shirt compute (demo queries) | ~$0-5/month |
| **Total (no Bastion)** | | **~$14-17/month** |

> **Tip:** Run `make destroy` when not actively demoing to eliminate all costs. The Terraform state is preserved locally so you can redeploy in ~8 minutes.

---

## Project Structure

```
zero-trust-gateway2/
├── app/                          # FastAPI application source
│   ├── main.py                   # App entrypoint, middleware, lifespan
│   ├── routers/
│   │   ├── health.py             # GET /health, GET /health/snowflake
│   │   └── data.py               # GET /data/metrics (Snowflake query)
│   ├── services/
│   │   ├── keyvault_client.py    # Azure Key Vault secret fetcher (UAMI)
│   │   └── snowflake_client.py   # Snowflake connector wrapper
│   └── pyproject.toml
│
├── cloud-init/
│   ├── cloud-init.yaml.tpl       # Terraform template → VM custom_data
│   ├── bootstrap-cloudflared.sh  # IMDS → Key Vault → tunnel token
│   └── README.md                 # Cloud-init deep dive
│
├── systemd/
│   ├── fastapi-gateway.service   # uvicorn as gateway user
│   └── cloudflared.service       # tunnel agent, reads /etc/cloudflared/env
│
├── terraform/
│   ├── main.tf                   # Provider config + module wiring
│   ├── variables.tf              # Root variable declarations
│   ├── outputs.tf                # tunnel_url, vm_private_ip, test_urls
│   ├── terraform.tfvars          # YOUR secrets (gitignored)
│   ├── terraform.tfvars.example  # Template to copy
│   └── modules/
│       ├── azure/                # VM, VNet, NSG, Key Vault PE, Managed Identity
│       ├── cloudflare/           # Tunnel, DNS record, Access app (optional)
│       └── snowflake/            # DB, schema, table, GATEWAY_SVC, network policy
│
├── scripts/
│   ├── bootstrap.sh              # Pre-flight checks + terraform init
│   ├── deploy.sh                 # Full deploy + cloud-init poll + health check
│   └── destroy.sh                # Teardown with confirmation
│
├── Makefile                      # make apply / logs / vm-status / test-*
└── .env.example                  # TF_VAR_* template for .env approach
```

---

## Troubleshooting

### Tunnel shows inactive after apply

Cloud-init takes 5-8 minutes. Check progress:
```bash
make vm-status
make logs
```

### bootstrap-cloudflared.sh: bash\r: No such file or directory

CRLF line endings in the script (Windows). Fixed by `sed -i 's/\r//'` in cloud-init runcmd — already in the template.

### dpkg lock error during cloudflared install

The `package_update: true` lock may still be held. Fixed with `-o DPkg::Lock::Timeout=300` on apt-get commands — already in the template.

### az vm run-command times out

cloud-init may still be running and holding the VM extension agent. Wait 2-3 minutes and retry.

### Snowflake connection refused

Check that `snowflake_account` in tfvars matches your account identifier format exactly (e.g. `xy12345.us-east-1` — no `.snowflakecomputing.com`).

### Key Vault access denied from VM

Verify the Managed Identity has the `Key Vault Secrets User` role assignment on the Key Vault. This is set by Terraform in `modules/azure/main.tf`.
