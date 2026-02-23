# Cloud-Init — How It Works

Cloud-init runs **once on first VM boot** and fully configures the machine without any
manual SSH access. This is what makes the "no public IP" architecture work.

## Files

| File | Purpose |
|------|---------|
| `cloud-init.yaml.tpl` | Terraform template rendered into cloud-init YAML at `terraform apply` |
| `bootstrap-cloudflared.sh` | Fetches Cloudflare tunnel token from Key Vault using Managed Identity |

## Rendering

`cloud-init.yaml.tpl` is processed by Terraform's `templatefile()` function in
`modules/azure/main.tf`. Terraform substitutes:

- `${key_vault_uri}` — Key Vault URI (e.g. `https://kv-ztgw-demo.vault.azure.net/`)
- `${azure_client_id}` — Managed Identity client ID
- `*_b64` variables — `base64encode(file(...))` of each app file

The rendered YAML is passed to the VM as `custom_data = base64encode(rendered_yaml)`.

## Why base64-encoded file content?

The FastAPI app files and systemd unit files are embedded as `encoding: b64` write_files
entries. This avoids a conflict between:
- Terraform template syntax `${...}`
- Shell variable syntax `${VAR}` in the cloudflared systemd unit (`${TUNNEL_TOKEN}`)

## Boot sequence

```
1. VM boots (no public IP, Managed Identity attached)
2. cloud-init runs:
   a. Installs packages (python3.11, ufw, cloudflared, jq, curl)
   b. Configures UFW: deny all inbound, allow all outbound
   c. Writes /etc/environment: KEY_VAULT_URL, AZURE_CLIENT_ID
   d. Writes app files to /opt/gateway/
   e. Creates Python venv, installs FastAPI + dependencies
   f. Writes systemd units: fastapi-gateway.service, cloudflared.service
   g. Runs bootstrap-cloudflared.sh:
      - Polls IMDS until Managed Identity is ready (~30s after boot)
      - Gets Key Vault access token from IMDS
      - Fetches CLOUDFLARE-TUNNEL-TOKEN secret
      - Writes /etc/cloudflared/env (mode 600)
   h. systemctl start fastapi-gateway cloudflared
3. Cloudflare tunnel connects (outbound HTTPS to Cloudflare edge)
4. Traffic can now flow: Cloudflare → tunnel → localhost:8000
```

## Viewing cloud-init logs

```bash
# From Azure portal → VM → Run command:
cat /var/log/cloud-init-output.log
cat /var/log/bootstrap-cloudflared.log

# Or via make:
make logs
```

## Timing

From `terraform apply` completing to a working tunnel endpoint: **~5-8 minutes**
- VM provisioning: ~1 min
- Package installation: ~2-3 min
- Python venv + pip install: ~1-2 min
- Key Vault bootstrap: ~30s (IMDS ready)
- cloudflared tunnel connect: ~10s
