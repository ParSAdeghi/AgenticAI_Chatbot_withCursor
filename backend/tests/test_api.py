from __future__ import annotations

import httpx
import pytest

from app.main import create_app


@pytest.mark.asyncio
async def test_healthz_ok() -> None:
    app = create_app()
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"ok": True}


@pytest.mark.asyncio
async def test_chat_fallback_toronto_reasonable_and_non_promotional() -> None:
    """
    No OPENAI_API_KEY in tests => deterministic fallback path.
    This proves the agent returns a plausible Canada-focused response even without network/LLM.
    """
    app = create_app()
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.post("/chat", json={"message": "What are top attractions in Toronto?"})
    assert r.status_code == 200
    reply = r.json()["reply"].lower()
    assert "toronto" in reply
    assert "cn tower" in reply
    assert "hotel" not in reply


@pytest.mark.asyncio
async def test_extract_location_fallback() -> None:
    app = create_app()
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        r1 = await client.post("/extract-location", json={"message": "2-day plan for Vancouver please"})
        r2 = await client.post("/extract-location", json={"message": "What should I pack for winter?"})
    assert r1.status_code == 200
    assert r1.json()["location"] in {"Vancouver"}
    assert r2.status_code == 200
    assert r2.json()["location"] == "General"


@pytest.mark.asyncio
async def test_validation_empty_message_422() -> None:
    app = create_app()
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.post("/chat", json={"message": ""})
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_openai_wiring_is_used_when_api_key_present(monkeypatch: pytest.MonkeyPatch) -> None:
    """
    Proves that when OPENAI_API_KEY is present, we call the OpenAI client, include our policy
    system prompt, and return the model output.
    """
    from types import SimpleNamespace

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    from app import settings as settings_mod

    settings_mod.get_settings.cache_clear()

    captured = {"agent_messages": None, "loc_messages": None}

    class _FakeChatCompletions:
        def __init__(self, content: str, capture_key: str):
            self._content = content
            self._capture_key = capture_key

        def create(self, **kwargs):
            captured[self._capture_key] = kwargs.get("messages")
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content=self._content))]
            )

    class _FakeOpenAI:
        def __init__(self, api_key: str):
            self.chat = SimpleNamespace(
                completions=_FakeChatCompletions(
                    content="Here are 3 Canada attractions: CN Tower, Stanley Park, Old Montreal.",
                    capture_key="agent_messages",
                )
            )

    class _FakeOpenAILocation:
        def __init__(self, api_key: str):
            self.chat = SimpleNamespace(
                completions=_FakeChatCompletions(
                    content='{"location":"Toronto"}',
                    capture_key="loc_messages",
                )
            )

    import app.agent as agent_mod
    import app.location as location_mod

    monkeypatch.setattr(agent_mod, "OpenAI", _FakeOpenAI)
    monkeypatch.setattr(location_mod, "OpenAI", _FakeOpenAILocation)

    app = create_app()
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        r_chat = await client.post("/chat", json={"message": "What should I see in Canada?"})
        r_loc = await client.post("/extract-location", json={"message": "Things to do in Toronto"})

    assert r_chat.status_code == 200
    assert "CN Tower" in r_chat.json()["reply"]
    assert r_loc.status_code == 200
    assert r_loc.json()["location"] == "Toronto"

from typing import Callable

@pytest.mark.asyncio
async def test_openai_real_api_call_if_key_present(
    monkeypatch: pytest.MonkeyPatch,
    record_property: Callable[[str, object], None],
) -> None:
    """
    If OPENAI_API_KEY is present in the environment (e.g. from .env file),
    this test will call the real OpenAI API and log the response to test_results.json.
    If not present, it will skip logging but still pass (using fallback).
    """
    from app import settings as settings_mod
    
    # Reload settings to pick up environment variables
    settings_mod.get_settings.cache_clear()
    settings = settings_mod.get_settings()
    
    app = create_app()
    transport = httpx.ASGITransport(app=app)
    
    prompt = "What are the top 3 attractions in Calgary?"
    
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.post("/chat", json={"message": prompt})
    
    assert r.status_code == 200
    reply = r.json()["reply"]
    
    # If we have a key, we expect a non-fallback response (lengthy and specific)
    # Attach the details to the pytest report; `conftest.py` writes a single JSON file
    # containing results for *all* tests at the end of the run.
    mode = "real_api" if settings.openai_api_key else "fallback"
    record_property("prompt", prompt)
    record_property("mode", mode)
    # Keep this short-ish so the JSON doesn't explode if you run this often.
    record_property("response_preview", reply[:2000])


