#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"

cleanup() {
  echo ""
  echo "[run_wsl] Stopping servers..."
  if [[ -n "${BACKEND_PID:-}" ]]; then 
    kill "$BACKEND_PID" 2>/dev/null || true
    echo "[run_wsl] Backend stopped"
  fi
  if [[ -n "${FRONTEND_PID:-}" ]]; then 
    kill "$FRONTEND_PID" 2>/dev/null || true
    echo "[run_wsl] Frontend stopped"
  fi
  exit 0
}
trap cleanup EXIT INT TERM

echo "=========================================="
echo "  Canada Tourist Chatbot - Starting"
echo "=========================================="
echo ""

# Verify Python3 is available in WSL (needed for port checks and venv)
if ! command -v python3 &> /dev/null; then
  echo "[run_wsl] ERROR: python3 not found in WSL. Please install Python 3.12+"
  exit 1
fi

is_port_free() {
  local port="$1"
  python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
PY
}

kill_port() {
  local port="$1"
  # Try from within WSL first
  if command -v lsof &> /dev/null; then
    lsof -t -i:"$port" | xargs -r kill -9 2>/dev/null || true
  elif command -v fuser &> /dev/null; then
    fuser -k "${port}/tcp" 2>/dev/null || true
  fi

  # If still busy, it may be held by a Windows process. Try killing via PowerShell.
  if ! is_port_free "$port"; then
    if command -v powershell.exe &> /dev/null; then
      powershell.exe -NoProfile -Command "\
        \$p=${port}; \
        \$conns = Get-NetTCPConnection -LocalPort \$p -ErrorAction SilentlyContinue; \
        \$pids = \$conns | Select-Object -ExpandProperty OwningProcess -Unique; \
        foreach (\$pid in \$pids) { \
          try { Stop-Process -Id \$pid -Force -ErrorAction SilentlyContinue } catch {} \
        }" 2>/dev/null || true
    fi
  fi
}

# Kill existing processes on ports 8000 and 3000 (verify they are actually free)
echo "[run_wsl] Checking for existing processes on ports 8000 and 3000..."
kill_port 8000
kill_port 3000

if is_port_free 8000; then
  echo "[run_wsl] ✓ Port 8000 is free"
else
  echo "[run_wsl] ⚠ WARNING: Port 8000 is still in use. Backend may fail to start."
fi

if is_port_free 3000; then
  echo "[run_wsl] ✓ Port 3000 is free"
else
  echo "[run_wsl] ERROR: Port 3000 is still in use."
  echo "[run_wsl]   Close whatever is using :3000 (often another Next.js dev server), then rerun ./run_wsl.sh"
  echo "[run_wsl]   Tip: In WSL you can run: lsof -ti:3000 | xargs -r kill -9"
  exit 1
fi

# Start Backend
echo "[run_wsl] Starting backend on :8000"
cd "$BACKEND_DIR"
UV_AVAILABLE=true
if ! command -v uv &> /dev/null; then
  UV_AVAILABLE=false
  if [[ -d ".venv-wsl" ]]; then
    echo "[run_wsl] ⚠ WARNING: uv not found, but .venv-wsl exists. Continuing without uv sync."
  else
    echo "[run_wsl] ERROR: uv not found and no .venv-wsl exists. Please install uv first:"
    echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
  fi
fi

# Always use WSL-specific venv to avoid Windows-created venv conflicts
echo "[run_wsl] Checking Linux-compatible virtual environment..."

PYTHON_VERSION=$(python3 --version)
echo "[run_wsl] Using Python: $PYTHON_VERSION"

# Check for OPENAI_API_KEY
if ! grep -q "OPENAI_API_KEY" "$BACKEND_DIR/.env" 2>/dev/null && ! grep -q "OPENAI_API_KEY" "$ROOT_DIR/.env" 2>/dev/null; then
  echo "----------------------------------------------------------------"
  echo "⚠ WARNING: OPENAI_API_KEY not found in .env files"
  echo "  The agent will run in FALLBACK MODE (mocked responses)."
  echo "  To use the real OpenAI API, add OPENAI_API_KEY to backend/.env"
  echo "----------------------------------------------------------------"
else
  echo "[run_wsl] ✓ OPENAI_API_KEY found"
fi

# Use WSL-specific venv location
export UV_PROJECT_ENVIRONMENT=.venv-wsl

# Clean up all venv directories except the final working one (.venv-wsl)
echo "[run_wsl] Cleaning up old/unused venv directories..."
VENV_CLEANED=false
VENV_REMOVAL_FAILED=false

# Function to aggressively remove a directory
remove_venv_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  
  echo "[run_wsl]   Attempting to remove $dir..."
  
  # Try multiple removal methods
  if rm -rf "$dir" 2>/dev/null; then
    return 0
  fi
  
  # If rm fails, try renaming first (breaks file locks)
  if mv "$dir" "${dir}.deleting" 2>/dev/null; then
    sleep 1
    if rm -rf "${dir}.deleting" 2>/dev/null; then
      return 0
    fi
  fi
  
  # If still fails, try from Windows side via PowerShell
  local win_path=$(wslpath -w "$(pwd)/$dir" 2>/dev/null)
  if [[ -n "$win_path" ]]; then
    if powershell.exe -Command "Remove-Item -Recurse -Force '$win_path' -ErrorAction SilentlyContinue" 2>/dev/null; then
      sleep 1
      if [[ ! -d "$dir" ]]; then
        return 0
      fi
    fi
  fi
  
  return 1
}

# Remove Windows-created .venv
if [[ -d ".venv" ]]; then
  if remove_venv_dir ".venv"; then
    echo "[run_wsl]   ✓ Removed .venv"
    VENV_CLEANED=true
  else
    echo "[run_wsl]   ⚠ WARNING: Could not remove .venv (file locks from Windows)"
    echo "[run_wsl]   You may need to close any Python processes and delete it manually"
    VENV_REMOVAL_FAILED=true
  fi
fi

# Remove backup Windows venv
if [[ -d ".venv.windows-backup" ]]; then
  if remove_venv_dir ".venv.windows-backup"; then
    echo "[run_wsl]   ✓ Removed .venv.windows-backup"
    VENV_CLEANED=true
  fi
fi

# Remove any other venv-related directories (except .venv-wsl)
shopt -s nullglob
for dir in .venv-*; do
  if [[ -d "$dir" ]] && [[ "$dir" != ".venv-wsl" ]] && [[ "$dir" != ".venv-wsl.deleting" ]]; then
    if remove_venv_dir "$dir"; then
      echo "[run_wsl]   ✓ Removed $dir"
      VENV_CLEANED=true
    fi
  fi
done
shopt -u nullglob

if [[ "$VENV_CLEANED" == "true" ]]; then
  echo "[run_wsl] ✓ Cleanup complete"
elif [[ "$VENV_REMOVAL_FAILED" == "true" ]]; then
  echo "[run_wsl] ⚠ Some venv directories could not be removed (Windows file locks)"
  echo "[run_wsl]   The script will continue, but you may want to manually delete .venv"
else
  echo "[run_wsl] ✓ No old venv directories to clean"
fi

# Check if WSL venv exists and is valid (Linux-compatible)
VENV_VALID=false
if [[ -d ".venv-wsl" ]]; then
  # Check if it has a Linux Python executable (not Windows .exe)
  if [[ -f ".venv-wsl/bin/python" ]] && [[ ! -f ".venv-wsl/Scripts/python.exe" ]]; then
    # Verify the Python executable actually works
    if .venv-wsl/bin/python --version &>/dev/null; then
      VENV_VALID=true
      echo "[run_wsl] ✓ Existing Linux-compatible venv found and valid"
    else
      echo "[run_wsl] ⚠ Existing venv found but Python executable is invalid"
    fi
  else
    echo "[run_wsl] ⚠ Existing venv found but appears to be Windows-compatible (has Scripts/python.exe)"
  fi
fi

# Create or recreate venv if needed
if [[ "$VENV_VALID" == "false" ]]; then
  if [[ -d ".venv-wsl" ]]; then
    echo "[run_wsl] Removing invalid/corrupted venv..."
    rm -rf .venv-wsl 2>/dev/null || true
  fi
  echo "[run_wsl] Creating Linux-compatible virtual environment..."
  # Explicitly create venv with Linux Python interpreter
  uv venv .venv-wsl --python python3
  echo "[run_wsl] ✓ Linux-compatible venv created"
fi

echo "[run_wsl] Installing/updating backend dependencies..."
if [[ "$UV_AVAILABLE" == "true" ]]; then
  uv sync
else
  echo "[run_wsl] Skipping uv sync (uv not available)"
fi

# Final cleanup: ensure only .venv-wsl exists
echo "[run_wsl] Final cleanup: ensuring only .venv-wsl remains..."
FINAL_CLEANUP=false
FINAL_CLEANUP_FAILED=false

# Remove specific known venv directories
for dir in .venv .venv.windows-backup; do
  if [[ -d "$dir" ]]; then
    if remove_venv_dir "$dir"; then
      FINAL_CLEANUP=true
    else
      FINAL_CLEANUP_FAILED=true
    fi
  fi
done

# Remove any other .venv-* directories (except .venv-wsl)
shopt -s nullglob
for dir in .venv-*; do
  if [[ -d "$dir" ]] && [[ "$dir" != ".venv-wsl" ]] && [[ "$dir" != ".venv-wsl.deleting" ]]; then
    if remove_venv_dir "$dir"; then
      FINAL_CLEANUP=true
    else
      FINAL_CLEANUP_FAILED=true
    fi
  fi
done
shopt -u nullglob

# Verify final state
if [[ -d ".venv" ]]; then
  echo "[run_wsl] ⚠ WARNING: .venv still exists (Windows file locks preventing removal)"
  echo "[run_wsl]   To remove it manually, run from PowerShell:"
  echo "[run_wsl]   Remove-Item -Recurse -Force backend\\.venv"
  FINAL_CLEANUP_FAILED=true
elif [[ "$FINAL_CLEANUP" == "true" ]]; then
  echo "[run_wsl] ✓ Cleanup complete - only .venv-wsl remains"
elif [[ "$FINAL_CLEANUP_FAILED" == "false" ]]; then
  echo "[run_wsl] ✓ Only .venv-wsl exists (no cleanup needed)"
fi

echo "[run_wsl] Running backend tests (pytest)..."
.venv-wsl/bin/python -m pytest || {
  echo "[run_wsl] WARNING: Tests failed, but continuing..."
}

echo "[run_wsl] Starting backend server..."
.venv-wsl/bin/python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 > /tmp/backend.log 2>&1 &
BACKEND_PID=$!

# Wait a moment for backend to start
sleep 2

# Start Frontend
echo ""
FRONTEND_PORT=3000
echo "[run_wsl] Starting frontend on :$FRONTEND_PORT"
cd "$FRONTEND_DIR"

if ! command -v npm &> /dev/null; then
  echo "[run_wsl] ERROR: npm not found. Please install Node.js first."
  exit 1
fi

echo "[run_wsl] Installing frontend dependencies..."
npm install

echo "[run_wsl] Starting frontend server..."
npm run dev -- --port "$FRONTEND_PORT" > /tmp/frontend.log 2>&1 &
FRONTEND_PID=$!

# Wait a moment for frontend to start
sleep 3

echo ""
echo "=========================================="
echo "  Servers Started Successfully!"
echo "=========================================="
echo ""
echo "  Backend:  http://localhost:8000"
echo "  Frontend: http://localhost:$FRONTEND_PORT"
echo "  API Docs: http://localhost:8000/docs"
echo ""
echo "  Backend PID:  $BACKEND_PID"
echo "  Frontend PID: $FRONTEND_PID"
echo ""
echo "  Logs:"
echo "    Backend:  tail -f /tmp/backend.log"
echo "    Frontend: tail -f /tmp/frontend.log"
echo ""
echo "  Press Ctrl+C to stop both servers"
echo "=========================================="
echo ""

# Stream logs instead of just waiting
tail -f /tmp/backend.log /tmp/frontend.log &
TAIL_PID=$!

wait $BACKEND_PID $FRONTEND_PID $TAIL_PID
