from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Optional

from openai import OpenAI

from .schemas import HistoryItem
from .settings import Settings


SYSTEM_PROMPT = """You are a helpful travel assistant focused on tourist attractions and trip planning in Canada.

Hard rules:
- Do NOT promote or advertise any business.
- Do NOT mention specific hotel names, restaurant names, tour operator names, or other specific business names/brands.
- If the user asks for hotels, lodging, restaurants, tours, or booking: give neutral guidance using criteria (neighborhood, safety, transit, budget, seasonality, accessibility, amenities) and categories (e.g., boutique hotel, hostel, family-friendly chain) without naming any businesses.
- Prefer practical, safe, family-friendly advice. If you are unsure, say so and ask a clarifying question.

Style:
- Be concise, structured, and location-specific.
- Use bullet points and day-by-day plans when helpful.
"""


@dataclass(frozen=True)
class ChatMsg:
    role: str
    content: str


def _fallback_reply(user_message: str) -> str:
    msg = user_message.lower()
    if "toronto" in msg:
        return (
            "Top Toronto attractions (non-promotional):\n"
            "- CN Tower and the waterfront area\n"
            "- Royal Ontario Museum\n"
            "- Distillery Historic District\n"
            "- St. Lawrence Market area\n"
            "- High Park (great in spring/fall)\n"
            "- Day trip idea: Niagara Falls\n"
        )
    if "vancouver" in msg:
        return (
            "A simple Vancouver plan (non-promotional):\n"
            "- Day 1: Stanley Park + Seawall, Granville Island, Gastown walk\n"
            "- Day 2: Capilano area or Grouse area (weather-dependent), Kitsilano beach area\n"
            "- Optional: Vancouver Aquarium/Science World (good for families)\n"
        )
    if "montreal" in msg or "montréal" in msg:
        return (
            "Highlights in Montreal (non-promotional):\n"
            "- Old Montreal walking loop (historic streets)\n"
            "- Mount Royal viewpoint\n"
            "- Montreal Museum of Fine Arts\n"
            "- Jean-Talon / Atwater market areas\n"
            "- Seasonal: festivals in summer, outdoor skating in winter\n"
        )
    if "alberta" in msg or "banff" in msg or "jasper" in msg:
        return (
            "Alberta Rockies ideas (non-promotional):\n"
            "- Banff: Lake Louise / Moraine Lake (check shuttle/season access), easy hikes\n"
            "- Icefields Parkway scenic drive\n"
            "- Jasper: Maligne Lake area, stargazing (dark skies)\n"
            "- Safety: pack layers, plan for rapid weather changes\n"
        )
    return (
        "Tell me the Canadian city/province (and your dates/budget/interests), and I’ll suggest top attractions, a simple itinerary, and practical tips—without promoting any businesses."
    )


def _to_openai_messages(message: str, history: Optional[Iterable[HistoryItem]]) -> List[dict]:
    msgs: List[dict] = [{"role": "system", "content": SYSTEM_PROMPT}]
    if history:
        for h in history:
            msgs.append({"role": h.role, "content": h.content})
    msgs.append({"role": "user", "content": message})
    return msgs


def generate_reply(message: str, history: Optional[List[HistoryItem]], settings: Settings) -> str:
    if not settings.openai_api_key or not settings.openai_api_key.get_secret_value():
        return _fallback_reply(message)

    client = OpenAI(api_key=settings.openai_api_key.get_secret_value())
    completion = client.chat.completions.create(
        model=settings.openai_model,
        messages=_to_openai_messages(message, history),
        temperature=0.4,
    )
    text = (completion.choices[0].message.content or "").strip()
    return text or _fallback_reply(message)

