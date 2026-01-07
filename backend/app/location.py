from __future__ import annotations

import json

from typing import List, Optional

from openai import OpenAI

from .schemas import HistoryItem
from .settings import Settings


LOCATION_SYSTEM_PROMPT = """You extract a single Canadian location label from the user message, considering the chat history for context.

Return JSON only: {"location": "<Label>"} where <Label> is a short location name like a city, province, or region in Canada.
If the message is ambiguous or not about a specific place, even after checking history, return {"location":"General"}.

Examples:
User: "Things to do in Toronto" -> {"location":"Toronto"}
User: "What about the food there?" (Context: Toronto) -> {"location":"Toronto"}
User: "2-day plan for Vancouver" -> {"location":"Vancouver"}
User: "Best time to visit Alberta?" -> {"location":"Alberta"}
User: "What should I pack?" -> {"location":"General"}
"""


def _heuristic_location(message: str) -> str:
    m = message.lower()
    candidates = [
        "toronto",
        "vancouver",
        "montreal",
        "calgary",
        "edmonton",
        "ottawa",
        "quebec",
        "alberta",
        "british columbia",
        "bc",
        "ontario",
        "manitoba",
        "saskatchewan",
        "nova scotia",
        "new brunswick",
        "newfoundland",
        "pei",
        "prince edward island",
        "yukon",
        "nunavut",
        "northwest territories",
        "banff",
        "jasper",
    ]
    for c in candidates:
        if c in m:
            if c == "bc":
                return "British Columbia"
            if c == "pei":
                return "Prince Edward Island"
            return c.title()
    return "General"


def extract_location(message: str, history: Optional[List[HistoryItem]], settings: Settings) -> str:
    if not settings.openai_api_key or not settings.openai_api_key.get_secret_value():
        return _heuristic_location(message)

    client = OpenAI(api_key=settings.openai_api_key.get_secret_value())
    
    msgs = [{"role": "system", "content": LOCATION_SYSTEM_PROMPT}]
    if history:
        for h in history:
            msgs.append({"role": h.role, "content": h.content})
    msgs.append({"role": "user", "content": message})

    completion = client.chat.completions.create(
        model=settings.openai_location_model,
        messages=msgs,
        temperature=0,
        response_format={"type": "json_object"},
    )
    raw = (completion.choices[0].message.content or "").strip()
    try:
        data = json.loads(raw)
        loc = (data.get("location") or "").strip()
        return loc or "General"
    except Exception:
        return _heuristic_location(message)

