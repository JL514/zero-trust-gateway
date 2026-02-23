import time
from typing import Optional

from azure.core.exceptions import ServiceRequestError
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient


class KeyVaultClient:
    """
    Azure Key Vault secrets client using DefaultAzureCredential.

    Authentication chain (in order):
      1. On VM:     Managed Identity (AZURE_CLIENT_ID env var selects the user-assigned identity)
      2. Locally:   `az login` CLI credential
      3. CI/CD:     AZURE_CLIENT_ID + AZURE_CLIENT_SECRET + AZURE_TENANT_ID env vars

    The vault is only reachable from the VM subnet via Private Endpoint.
    Local usage requires a VPN or Azure Bastion port-forwarding.
    """

    def __init__(self, vault_url: str) -> None:
        self.vault_url = vault_url.rstrip("/")
        credential = DefaultAzureCredential()
        self._client = SecretClient(vault_url=self.vault_url, credential=credential)

    def get_secret(self, name: str, max_attempts: int = 3) -> str:
        """
        Retrieve a secret value with exponential backoff retry on transient errors.
        Non-retryable errors (403 Forbidden, 404 Not Found) are raised immediately.
        """
        delay = 1.0
        last_exc: Optional[Exception] = None

        for attempt in range(max_attempts):
            try:
                return self._client.get_secret(name).value
            except ServiceRequestError as exc:
                # Transient network error — retry with backoff
                last_exc = exc
                if attempt < max_attempts - 1:
                    time.sleep(delay)
                    delay *= 2
            except Exception:
                # Non-retryable (auth failure, secret not found, etc.)
                raise

        raise last_exc  # type: ignore[misc]

    def list_secrets(self) -> list[str]:
        """Return secret names — used by the /health/keyvault endpoint."""
        return [s.name for s in self._client.list_properties_of_secrets()]
