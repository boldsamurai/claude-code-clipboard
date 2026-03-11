#!/usr/bin/env python3
"""
Claude Code Stop hook: extracts fenced code blocks from assistant responses
and copies each one to the system clipboard.

Supports: copyq, xclip, xsel, wl-copy (Wayland), pbcopy (macOS),
clip.exe and powershell.exe (WSL → Windows), win32yank (Windows/WSL).
Clipboard managers with history (copyq) get each block as a separate entry.
Simple clipboard tools get all blocks joined together.
"""

import json
import logging
import os
import re
import shutil
import subprocess
import sys
from enum import Enum
from logging.handlers import RotatingFileHandler
from pathlib import Path

LOG_PATH = Path.home() / ".claude" / "hooks" / "copy-code-blocks.log"
LOG_LEVEL = os.environ.get("CLAUDE_CLIPBOARD_LOG_LEVEL", "WARNING").upper()

logger = logging.getLogger("copy-code-blocks")
logger.setLevel(getattr(logging, LOG_LEVEL, logging.WARNING))

_handler = RotatingFileHandler(LOG_PATH, maxBytes=100_000, backupCount=1)
_handler.setFormatter(logging.Formatter("%(name)s: %(levelname)s: %(message)s"))
logger.addHandler(_handler)


class ClipboardBackend(Enum):
    COPYQ = "copyq"
    XCLIP = "xclip"
    XSEL = "xsel"
    WL_COPY = "wl-copy"
    PBCOPY = "pbcopy"
    # WSL → Windows clipboard
    CLIP_EXE = "clip.exe"
    POWERSHELL = "powershell.exe"
    # Windows/WSL clipboard tool (often used with neovim)
    WIN32YANK = "win32yank"


# Backends that support clipboard history (each block = separate entry)
HISTORY_BACKENDS = {ClipboardBackend.COPYQ}

# Detection order: prefer history-capable backends first, then platform-specific
DETECTION_ORDER = [
    ClipboardBackend.COPYQ,
    ClipboardBackend.PBCOPY,
    ClipboardBackend.WL_COPY,
    ClipboardBackend.XCLIP,
    ClipboardBackend.XSEL,
    ClipboardBackend.WIN32YANK,
    ClipboardBackend.CLIP_EXE,
    ClipboardBackend.POWERSHELL,
]


def detect_backend() -> ClipboardBackend | None:
    """Detect available clipboard backend, preferring history-capable ones."""
    for backend in DETECTION_ORDER:
        if shutil.which(backend.value):
            return backend
    return None


def copy_to_clipboard(text: str, backend: ClipboardBackend) -> None:
    """Copy text to clipboard using the specified backend."""
    env = os.environ.copy()
    result = None

    try:
        match backend:
            case ClipboardBackend.COPYQ:
                result = subprocess.run(
                    ["copyq", "add", "--", text],
                    env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.XCLIP:
                result = subprocess.run(
                    ["xclip", "-selection", "clipboard"],
                    input=text.encode(), env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.XSEL:
                result = subprocess.run(
                    ["xsel", "--clipboard", "--input"],
                    input=text.encode(), env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.WL_COPY:
                result = subprocess.run(
                    ["wl-copy", "--", text],
                    env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.PBCOPY:
                result = subprocess.run(
                    ["pbcopy"],
                    input=text.encode(), env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.CLIP_EXE:
                result = subprocess.run(
                    ["clip.exe"],
                    input=text.encode("utf-16-le"), env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.POWERSHELL:
                result = subprocess.run(
                    ["powershell.exe", "-NoProfile", "-Command", "Set-Clipboard", "-Value", text],
                    env=env, check=False, timeout=5,
                    capture_output=True,
                )
            case ClipboardBackend.WIN32YANK:
                result = subprocess.run(
                    ["win32yank", "-i", "--crlf"],
                    input=text.encode(), env=env, check=False, timeout=5,
                    capture_output=True,
                )

        if result and result.returncode != 0:
            stderr = result.stderr.decode(errors="replace").strip()
            logger.warning("%s exited with code %d: %s", backend.value, result.returncode, stderr)
    except subprocess.TimeoutExpired:
        logger.warning("%s timed out after 5s", backend.value)


def extract_code_blocks(text: str) -> list[str]:
    """Extract content from fenced code blocks (``` or ```` etc.)."""
    pattern = r"(`{3,})[^\n]*\n(.*?)\1"
    return [m[1] for m in re.findall(pattern, text, re.DOTALL)]


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        logger.warning("Invalid JSON on stdin")
        return

    message = data.get("last_assistant_message")
    if not isinstance(message, str) or not message:
        logger.debug("No assistant message — skipping")
        return

    blocks = extract_code_blocks(message)
    if not blocks:
        logger.debug("No code blocks found — skipping")
        return

    backend = detect_backend()
    if backend is None:
        logger.warning("No clipboard backend found — install one of: copyq, xclip, xsel, wl-copy, pbcopy, clip.exe, win32yank")
        return

    logger.debug("Found %d code block(s), using %s", len(blocks), backend.value)

    if backend in HISTORY_BACKENDS:
        # Each block as a separate clipboard entry (reversed so first = newest)
        for block in reversed(blocks):
            content = block.rstrip("\n")
            if content:
                copy_to_clipboard(content, backend)
    else:
        # No history — join all blocks with double newlines
        combined = "\n\n".join(b.rstrip("\n") for b in blocks if b.strip())
        if combined:
            copy_to_clipboard(combined, backend)


if __name__ == "__main__":
    main()
