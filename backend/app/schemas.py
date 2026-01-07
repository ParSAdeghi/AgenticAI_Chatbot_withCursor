from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel, Field


Role = Literal["user", "assistant"]


class HistoryItem(BaseModel):
    role: Role
    content: str = Field(min_length=1, max_length=10_000)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10_000)
    history: Optional[List[HistoryItem]] = None


class ChatResponse(BaseModel):
    reply: str


class ExtractLocationRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10_000)
    history: Optional[List[HistoryItem]] = None


class ExtractLocationResponse(BaseModel):
    location: str

