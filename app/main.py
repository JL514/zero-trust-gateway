import json
import socket
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware

from routers import data, health
from services.keyvault_client import KeyVaultClient


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Fetch Snowflake credentials from Key Vault on startup and store in app.state."""
    import os

    kv_url = os.environ["KEY_VAULT_URL"]
    kv = KeyVaultClient(kv_url)

    app.state.snowflake_account = kv.get_secret("SNOWFLAKE-ACCOUNT")
    app.state.snowflake_user = kv.get_secret("SNOWFLAKE-USER")
    app.state.snowflake_password = kv.get_secret("SNOWFLAKE-PASSWORD")
    app.state.kv_client = kv

    yield


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Structured JSON request logging — captured by journald and forwarded to Log Analytics."""

    async def dispatch(self, request: Request, call_next):
        start = time.monotonic()
        response = await call_next(request)
        duration_ms = round((time.monotonic() - start) * 1000, 2)

        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "method": request.method,
            "path": str(request.url.path),
            "status_code": response.status_code,
            "duration_ms": duration_ms,
            "hostname": socket.gethostname(),
            "client_ip": request.client.host if request.client else "unknown",
        }
        print(json.dumps(log_entry), flush=True)
        return response


app = FastAPI(
    title="Zero Trust Gateway",
    description=(
        "Secure data gateway: Cloudflare Zero Trust → Linux VM (no public IP) "
        "→ Azure Key Vault (Private Endpoint) → Snowflake (network policy)"
    ),
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(RequestLoggingMiddleware)
app.include_router(health.router)
app.include_router(data.router)
