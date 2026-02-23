#cloud-config
# Zero Trust Gateway — Cloud-Init Bootstrap Template
#
# This file is rendered by Terraform's templatefile() function in modules/azure/main.tf.
# Terraform substitutes:
#   ${key_vault_uri}     — Key Vault URI (e.g. https://kv-ztgw-demo.vault.azure.net/)
#   ${azure_client_id}   — Managed Identity client ID
#   *_b64 variables      — base64-encoded file contents (avoids YAML/Terraform escaping)
#
# Do NOT render this file manually. Use: terraform apply

hostname: zero-trust-gateway
fqdn: zero-trust-gateway.internal
manage_etc_hosts: true

# ── System users ──────────────────────────────────────────────────────────────
users:
  - name: gateway
    system: true
    shell: /usr/sbin/nologin
    home: /opt/gateway
    no_create_home: false
    comment: "Zero Trust Gateway service account"

# ── Package installation ──────────────────────────────────────────────────────
package_update: true
package_upgrade: false

packages:
  - python3.11
  - python3.11-venv
  - python3-pip
  - curl
  - jq
  - git
  - ufw
  - apt-transport-https

# ── Write files ───────────────────────────────────────────────────────────────
# App Python files and systemd units are base64-encoded so their content doesn't
# conflict with Terraform's $${} interpolation syntax.
write_files:

  # Environment variables (injected by Terraform at plan time)
  - path: /etc/environment
    content: |
      KEY_VAULT_URL=${key_vault_uri}
      AZURE_CLIENT_ID=${azure_client_id}
    append: false

  # FastAPI application
  # Note: written as root — runcmd does chown -R gateway:gateway /opt/gateway after user exists
  - path: /opt/gateway/main.py
    encoding: b64
    content: ${main_py_b64}
    permissions: "0644"

  - path: /opt/gateway/routers/__init__.py
    encoding: b64
    content: ${routers_init_b64}
    permissions: "0644"

  - path: /opt/gateway/routers/health.py
    encoding: b64
    content: ${health_py_b64}
    permissions: "0644"

  - path: /opt/gateway/routers/data.py
    encoding: b64
    content: ${data_py_b64}
    permissions: "0644"

  - path: /opt/gateway/services/__init__.py
    encoding: b64
    content: ${services_init_b64}
    permissions: "0644"

  - path: /opt/gateway/services/snowflake_client.py
    encoding: b64
    content: ${snowflake_client_b64}
    permissions: "0644"

  - path: /opt/gateway/services/keyvault_client.py
    encoding: b64
    content: ${keyvault_client_b64}
    permissions: "0644"

  # pyproject.toml for pip install --no-build-isolation
  - path: /opt/gateway/pyproject.toml
    content: |
      [build-system]
      requires = ["setuptools>=68"]
      build-backend = "setuptools.backends.legacy:build"

      [project]
      name = "zero-trust-gateway"
      version = "1.0.0"
      requires-python = ">=3.11"
      dependencies = [
        "fastapi>=0.109",
        "uvicorn[standard]>=0.27",
        "snowflake-connector-python>=3.6",
        "azure-identity>=1.15",
        "azure-keyvault-secrets>=4.7",
        "pydantic>=2.0",
        "pydantic-settings>=2.0",
      ]
    permissions: "0644"

  # Systemd units (base64-encoded — cloudflared.service contains shell vars
  # which must NOT be interpolated by Terraform)
  - path: /etc/systemd/system/fastapi-gateway.service
    encoding: b64
    content: ${fastapi_svc_b64}
    permissions: "0644"

  - path: /etc/systemd/system/cloudflared.service
    encoding: b64
    content: ${cloudflared_svc_b64}
    permissions: "0644"

  # Bootstrap script to fetch tunnel token from Key Vault via IMDS
  - path: /usr/local/bin/bootstrap-cloudflared.sh
    encoding: b64
    content: ${bootstrap_script_b64}
    permissions: "0755"

# ── Run commands (sequential, executed as root at first boot) ─────────────────
runcmd:
  # Firewall: deny all inbound, allow all outbound (cloudflared is outbound-only)
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable

  # Install cloudflared from Cloudflare's official apt repo
  # -o DPkg::Lock::Timeout=300 lets apt wait up to 5 min for the lock instead of failing immediately
  - mkdir -p --mode=0755 /usr/share/keyrings
  - >
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg
    | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
  - >
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg]
    https://pkg.cloudflare.com/cloudflared jammy main"
    | tee /etc/apt/sources.list.d/cloudflared.list
  - apt-get update -qq -o DPkg::Lock::Timeout=300
  - apt-get install -y -o DPkg::Lock::Timeout=300 cloudflared

  # Create cloudflared system user if not already created by the package
  - id cloudflared || useradd --system --shell /usr/sbin/nologin cloudflared

  # Ensure directory structure exists with correct ownership
  - mkdir -p /opt/gateway/routers /opt/gateway/services
  - chown -R gateway:gateway /opt/gateway

  # Create Python venv and install application dependencies
  - python3.11 -m venv /opt/gateway/.venv
  - /opt/gateway/.venv/bin/pip install --quiet --upgrade pip
  - >
    /opt/gateway/.venv/bin/pip install --quiet
    fastapi "uvicorn[standard]" snowflake-connector-python
    azure-identity azure-keyvault-secrets pydantic pydantic-settings
  - chown -R gateway:gateway /opt/gateway/.venv

  # Strip Windows CRLF line endings from all files encoded on Windows
  - sed -i 's/\r//' /usr/local/bin/bootstrap-cloudflared.sh
  - sed -i 's/\r//' /etc/systemd/system/fastapi-gateway.service
  - sed -i 's/\r//' /etc/systemd/system/cloudflared.service

  # Bootstrap: fetch Cloudflare tunnel token from Key Vault using Managed Identity
  - /usr/local/bin/bootstrap-cloudflared.sh

  # Enable and start both services
  - systemctl daemon-reload
  - systemctl enable fastapi-gateway cloudflared
  - systemctl start fastapi-gateway
  - systemctl start cloudflared

final_message: |
  ╔══════════════════════════════════════════════════════╗
  ║  Zero Trust Gateway cloud-init complete              ║
  ║  FastAPI listening on 127.0.0.1:8000                 ║
  ║  Cloudflare tunnel daemon started                    ║
  ║  Logs: journalctl -u fastapi-gateway -u cloudflared  ║
  ╚══════════════════════════════════════════════════════╝
