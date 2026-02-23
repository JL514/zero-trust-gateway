from typing import Optional

import snowflake.connector
from snowflake.connector import DictCursor


class SnowflakeClient:
    """
    Thin wrapper around snowflake-connector-python.

    Supports use as a context manager for automatic connection cleanup:

        with SnowflakeClient(account=..., user=..., ...) as client:
            rows = client.execute_query("SELECT * FROM ...")

    Connections are reused within a request lifecycle (one connect per
    context manager entry, closed on exit).
    """

    def __init__(
        self,
        account: str,
        user: str,
        password: str,
        database: str,
        schema: str,
    ) -> None:
        self.account = account
        self.user = user
        self.password = password
        self.database = database
        self.schema = schema
        self._conn: Optional[snowflake.connector.SnowflakeConnection] = None

    # ── Connection lifecycle ───────────────────────────────────────────────────

    def connect(self) -> None:
        self._conn = snowflake.connector.connect(
            account=self.account,
            user=self.user,
            password=self.password,
            database=self.database,
            schema=self.schema,
            session_parameters={"QUERY_TAG": "zero-trust-gateway"},
        )

    def close(self) -> None:
        if self._conn and not self._conn.is_closed():
            self._conn.close()
        self._conn = None

    def __enter__(self) -> "SnowflakeClient":
        self.connect()
        return self

    def __exit__(self, *args) -> None:
        self.close()

    # ── Query execution ────────────────────────────────────────────────────────

    def execute_query(self, sql: str, params: Optional[tuple] = None) -> list[dict]:
        """Execute SQL and return results as a list of dicts (column name → value)."""
        if not self._conn or self._conn.is_closed():
            self.connect()

        cursor = self._conn.cursor(DictCursor)
        try:
            cursor.execute(sql, params)
            return cursor.fetchall()
        finally:
            cursor.close()
