import socket
from datetime import datetime, timezone

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
async def health_check():
    """Basic liveness check — returns VM hostname so you can verify which backend responded."""
    return {
        "status": "ok",
        "backend": "linux-vm",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "hostname": socket.gethostname(),
    }


@router.get("/snowflake")
async def health_snowflake(request: Request):
    """Verify Snowflake connectivity and measure round-trip latency."""
    import time

    from services.snowflake_client import SnowflakeClient

    start = time.monotonic()
    try:
        with SnowflakeClient(
            account=request.app.state.snowflake_account,
            user=request.app.state.snowflake_user,
            password=request.app.state.snowflake_password,
            database="DEMO_DB",
            schema="DEMO_SCHEMA",
        ) as client:
            client.execute_query("SELECT 1")
        latency_ms = round((time.monotonic() - start) * 1000, 2)
        return {"connected": True, "latency_ms": latency_ms}
    except Exception as exc:
        return JSONResponse(
            status_code=503,
            content={"connected": False, "error": str(exc)},
        )


@router.get("/keyvault")
async def health_keyvault(request: Request):
    """Verify Key Vault connectivity (uses the already-authenticated client from app.state)."""
    try:
        secrets = request.app.state.kv_client.list_secrets()
        return {"connected": True, "secret_count": len(secrets)}
    except Exception as exc:
        return JSONResponse(
            status_code=503,
            content={"connected": False, "error": str(exc)},
        )
