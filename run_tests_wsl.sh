#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"

echo "=========================================="
echo "  Canada Tourist Chatbot - Running Tests"
echo "=========================================="
echo ""

if ! command -v python3 &> /dev/null; then
  echo "[run_tests_wsl] ERROR: python3 not found in WSL. Please install Python 3.12+"
  exit 1
fi

cd "$BACKEND_DIR"

if [[ ! -x ".venv-wsl/bin/python" ]]; then
  echo "[run_tests_wsl] ERROR: backend/.venv-wsl not found (or not Linux-compatible)."
  echo "[run_tests_wsl] Run ./run_wsl.sh once to create it, then rerun this script."
  exit 1
fi

echo "[run_tests_wsl] Using: $("$BACKEND_DIR/.venv-wsl/bin/python" --version)"
echo "[run_tests_wsl] Running pytest..."

"$BACKEND_DIR/.venv-wsl/bin/python" -m pytest

