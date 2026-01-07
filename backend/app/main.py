from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .agent import generate_reply
from .location import extract_location
from .schemas import (
    ChatRequest,
    ChatResponse,
    ExtractLocationRequest,
    ExtractLocationResponse,
)
from .settings import get_settings


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(title="Canada Tourist Agent API", version="0.1.0")

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allow_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/healthz")
    def healthz() -> dict:
        return {"ok": True}

    @app.post("/chat", response_model=ChatResponse)
    def chat(req: ChatRequest) -> ChatResponse:
        reply = generate_reply(req.message, req.history, settings=settings)
        return ChatResponse(reply=reply)

    @app.post("/extract-location", response_model=ExtractLocationResponse)
    def extract_location_route(req: ExtractLocationRequest) -> ExtractLocationResponse:
        loc = extract_location(req.message, req.history, settings=settings)
        return ExtractLocationResponse(location=loc)

    return app


app = create_app()

