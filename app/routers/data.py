from fastapi import APIRouter, HTTPException, Request

from services.snowflake_client import SnowflakeClient

router = APIRouter(prefix="/data", tags=["data"])


def _get_client(request: Request) -> SnowflakeClient:
    """Build a SnowflakeClient from credentials stored in app.state (loaded from Key Vault at startup)."""
    return SnowflakeClient(
        account=request.app.state.snowflake_account,
        user=request.app.state.snowflake_user,
        password=request.app.state.snowflake_password,
        database="DEMO_DB",
        schema="DEMO_SCHEMA",
    )


@router.get("/metrics")
async def get_all_metrics(request: Request):
    """Return all rows from INFRASTRUCTURE_METRICS."""
    with _get_client(request) as client:
        return client.execute_query(
            "SELECT * FROM INFRASTRUCTURE_METRICS ORDER BY DATE, ENVIRONMENT, RESOURCE_TYPE"
        )


@router.get("/metrics/summary")
async def get_metrics_summary(request: Request):
    """Aggregate statistics across all environments and resource types."""
    with _get_client(request) as client:
        rows = client.execute_query(
            """
            SELECT
                ROUND(AVG(COST_USD), 2)       AS avg_cost_usd,
                SUM(INCIDENT_COUNT)           AS total_incidents,
                ROUND(AVG(MTTR_MINUTES), 2)   AS avg_mttr_minutes,
                ROUND(AVG(VM_UPTIME_PCT), 4)  AS avg_uptime_pct
            FROM INFRASTRUCTURE_METRICS
            """
        )
    return rows[0] if rows else {}


@router.get("/metrics/resource/{resource_type}")
async def get_metrics_by_resource(request: Request, resource_type: str):
    """Filter metrics by RESOURCE_TYPE (e.g. 'Linux VM', 'Key Vault', 'Snowflake Compute')."""
    with _get_client(request) as client:
        rows = client.execute_query(
            "SELECT * FROM INFRASTRUCTURE_METRICS WHERE RESOURCE_TYPE = %s ORDER BY DATE",
            params=(resource_type,),
        )
    if not rows:
        raise HTTPException(
            status_code=404,
            detail=f"No metrics found for resource_type: {resource_type}",
        )
    return rows


@router.get("/metrics/{environment}")
async def get_metrics_by_environment(request: Request, environment: str):
    """Filter metrics by ENVIRONMENT (prod, staging, dev).
    NOTE: This route is intentionally defined after /metrics/summary and
    /metrics/resource/{resource_type} so FastAPI matches literal paths first."""
    with _get_client(request) as client:
        rows = client.execute_query(
            "SELECT * FROM INFRASTRUCTURE_METRICS WHERE ENVIRONMENT = %s ORDER BY DATE",
            params=(environment,),
        )
    if not rows:
        raise HTTPException(
            status_code=404,
            detail=f"No metrics found for environment: {environment}",
        )
    return rows
