#!/bin/bash
set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="copy-code-blocks.py"
HOOK_COMMAND="python3 $HOOK_DIR/$SCRIPT_NAME"

echo "=== Claude Code Clipboard Hook — Install ==="
echo ""

# Check Python 3.10+ (needed for match/case)
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required but not found."
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 10 ]; }; then
    echo "ERROR: Python 3.10+ is required (found $PYTHON_VERSION)."
    exit 1
fi

echo "Python $PYTHON_VERSION — OK"

# Detect clipboard backends
echo ""
echo "Clipboard backends:"
FOUND_BACKEND=false
for cmd in copyq xclip xsel wl-copy pbcopy win32yank clip.exe powershell.exe; do
    if command -v "$cmd" &>/dev/null; then
        echo "  + $cmd (found)"
        FOUND_BACKEND=true
    fi
done

if [ "$FOUND_BACKEND" = false ]; then
    echo "  ERROR: No clipboard backend found."
    echo "  Install one of:"
    echo "    Linux X11:    copyq, xclip, xsel"
    echo "    Linux Wayland: wl-copy"
    echo "    macOS:        pbcopy (built-in)"
    echo "    WSL/Windows:  clip.exe (built-in), win32yank"
    exit 1
fi

# Copy script
mkdir -p "$HOOK_DIR"
cp "$SCRIPT_DIR/$SCRIPT_NAME" "$HOOK_DIR/$SCRIPT_NAME"
chmod +x "$HOOK_DIR/$SCRIPT_NAME"
echo ""
echo "Script installed to $HOOK_DIR/$SCRIPT_NAME"

# Register hook in settings.json
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

python3 << 'PYEOF'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
hook_command = "python3 " + os.path.expanduser("~/.claude/hooks/copy-code-blocks.py")

with open(settings_path) as f:
    settings = json.load(f)

hook_entry = {
    "hooks": [{
        "type": "command",
        "command": hook_command
    }]
}

hooks = settings.setdefault("hooks", {})
stop_hooks = hooks.setdefault("Stop", [])

already_installed = any(
    any(
        "copy-code-blocks" in h.get("command", "")
        for h in entry.get("hooks", [])
    )
    for entry in stop_hooks
)

if already_installed:
    print("Hook already registered in settings.json — skipping.")
else:
    stop_hooks.append(hook_entry)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("Hook registered in settings.json")

PYEOF

# Offer to add formatting instructions to global CLAUDE.md
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SECTION_MARKER="## Claude Code Clipboard Hook"

echo ""
echo "The hook works best when Claude uses fenced code blocks for all commands."
echo -n "Add formatting instructions to $CLAUDE_MD? [y/N] "
read -r REPLY

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    if [ -f "$CLAUDE_MD" ] && grep -qF "$SECTION_MARKER" "$CLAUDE_MD"; then
        echo "Already configured in $CLAUDE_MD — skipping."
    else
        if [ ! -f "$CLAUDE_MD" ]; then
            mkdir -p "$(dirname "$CLAUDE_MD")"
            touch "$CLAUDE_MD"
        fi
        # Ensure there's a blank line before our section
        if [ -s "$CLAUDE_MD" ] && [ "$(tail -c 1 "$CLAUDE_MD")" != "" ]; then
            echo "" >> "$CLAUDE_MD"
        fi
        cat >> "$CLAUDE_MD" << 'MDEOF'

## Claude Code Clipboard Hook
- Always use fenced code blocks (```) for commands and code the user should copy or run.
- Never use inline code (`) for commands — only for referencing names in prose.
MDEOF
        echo "Formatting instructions added to $CLAUDE_MD"
    fi
else
    echo "Skipped — you can add them manually later."
fi

echo ""
echo "=== Installation complete ==="
echo "Restart Claude Code to activate the hook."
echo "Every code block from Claude's responses will be copied to your clipboard."
