"""
Supabase client — uses direct REST (PostgREST) calls via requests.
This avoids supabase-py key format validation issues (sb_publishable_ support varies by version).
"""
import os
import requests

_SUPABASE_URL: str = ""
_SUPABASE_KEY: str = ""


def _init():
    global _SUPABASE_URL, _SUPABASE_KEY
    if not _SUPABASE_URL:
        _SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
        _SUPABASE_KEY = os.environ["SUPABASE_KEY"]


def _headers() -> dict:
    _init()
    return {
        "apikey": _SUPABASE_KEY,
        "Authorization": f"Bearer {_SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


class _Table:
    def __init__(self, name: str):
        self._name = name
        self._select_cols = "*"
        self._filters: list = []
        self._limit_val = None
        self._offset_val = None
        self._upsert_data = None
        self._on_conflict = None

    def select(self, columns: str = "*") -> "_Table":
        self._select_cols = columns
        return self

    def limit(self, n: int) -> "_Table":
        self._limit_val = n
        return self

    def offset(self, n: int) -> "_Table":
        self._offset_val = n
        return self

    def upsert(self, rows: list, on_conflict: str = "") -> "_Table":
        self._upsert_data = rows
        self._on_conflict = on_conflict
        return self

    def execute(self):
        _init()
        if self._upsert_data is not None:
            return self._do_upsert()
        return self._do_select()

    def _do_select(self):
        url = f"{_SUPABASE_URL}/rest/v1/{self._name}"
        params = {"select": self._select_cols}
        if self._limit_val is not None:
            params["limit"] = str(self._limit_val)
        if self._offset_val is not None:
            params["offset"] = str(self._offset_val)
        headers = _headers()
        # Request all rows (no range limit)
        headers["Range-Unit"] = "items"
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        resp.raise_for_status()
        return _Result(resp.json())

    def _do_upsert(self):
        url = f"{_SUPABASE_URL}/rest/v1/{self._name}"
        headers = _headers()
        if self._on_conflict:
            headers["Prefer"] = f"resolution=merge-duplicates,return=representation"
            url += f"?on_conflict={self._on_conflict}"
        resp = requests.post(url, headers=headers, json=self._upsert_data, timeout=30)
        resp.raise_for_status()
        return _Result(resp.json() if resp.text else [])


class _Result:
    def __init__(self, data):
        self.data = data if isinstance(data, list) else []


class _SupabaseClient:
    def table(self, name: str) -> _Table:
        return _Table(name)


_client: _SupabaseClient = _SupabaseClient()


def get_supabase() -> _SupabaseClient:
    return _client
