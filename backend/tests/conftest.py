from __future__ import annotations

import inspect
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

import pytest


def _results_path() -> Path:
    # backend/tests/conftest.py -> backend/
    return Path(__file__).resolve().parents[1] / "test_results.json"


def _description_for_item(item: pytest.Item) -> str:
    """
    Best-effort description for what a test checks.

    Priority:
    1) Test function docstring (first paragraph)
    2) Fallback based on test name
    """
    obj = getattr(item, "obj", None)
    doc = inspect.getdoc(obj) if obj is not None else None
    if doc:
        # Keep the first paragraph only (up to first blank line), and normalize whitespace.
        first_para = doc.split("\n\n", 1)[0].strip()
        return " ".join(first_para.split())

    name = getattr(item, "originalname", None) or getattr(item, "name", "")
    if "healthz" in name:
        return "Checks the /healthz endpoint returns 200 OK and {ok: true}."
    if "fallback_toronto" in name:
        return "Checks chat fallback mode returns a Toronto-relevant, non-promotional response when no API key is used."
    if "extract_location_fallback" in name:
        return "Checks location extraction fallback returns a specific location for a clear prompt and 'General' for ambiguous prompts."
    if "validation_empty_message" in name:
        return "Checks request validation rejects an empty message with a 422 response."
    if "openai_wiring_is_used" in name:
        return "Checks OpenAI client wiring is used when an API key is present (mocked OpenAI)."
    if "openai_real_api_call" in name:
        return "If an API key is present, calls the real OpenAI API; otherwise uses fallback. Records a response preview."
    return "Test description not provided."


def pytest_configure(config: pytest.Config) -> None:
    # Store session data on the config object (simple, no global state).
    config._json_report_run_at = datetime.now(timezone.utc).isoformat()  # type: ignore[attr-defined]
    config._json_report_results: List[Dict[str, Any]] = []  # type: ignore[attr-defined]


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item: pytest.Item, call: pytest.CallInfo[Any]):
    # Let pytest create the report first.
    outcome = yield
    report: pytest.TestReport = outcome.get_result()

    # Only record the actual test call outcome (skip setup/teardown noise).
    if report.when != "call":
        return

    props = {k: v for k, v in getattr(report, "user_properties", [])}

    item.config._json_report_results.append(  # type: ignore[attr-defined]
        {
            "test_name": report.nodeid,
            "description": _description_for_item(item),
            "outcome": report.outcome,  # "passed" | "failed" | "skipped"
            "duration_s": round(float(getattr(report, "duration", 0.0)), 6),
            **({"properties": props} if props else {}),
        }
    )


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    payload = {
        "run_at": session.config._json_report_run_at,  # type: ignore[attr-defined]
        "exitstatus": exitstatus,
        "results": session.config._json_report_results,  # type: ignore[attr-defined]
    }
    _results_path().write_text(json.dumps(payload, indent=2), encoding="utf-8")

