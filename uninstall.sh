#!/bin/bash
set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_NAME="copy-code-blocks.py"

echo "=== Claude Code Clipboard Hook — Uninstall ==="
echo ""

# Remove hook from settings.json
if [ -f "$SETTINGS" ]; then
    python3 << 'PYEOF'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
stop_hooks = hooks.get("Stop", [])

filtered = [
    entry for entry in stop_hooks
    if not any(
        "copy-code-blocks" in h.get("command", "")
        for h in entry.get("hooks", [])
    )
]

if len(filtered) < len(stop_hooks):
    hooks["Stop"] = filtered
    if not filtered:
        del hooks["Stop"]
    if not hooks:
        del settings["hooks"]
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("Hook removed from settings.json")
else:
    print("Hook not found in settings.json — nothing to remove.")

PYEOF
fi

# Remove script
if [ -f "$HOOK_DIR/$SCRIPT_NAME" ]; then
    rm "$HOOK_DIR/$SCRIPT_NAME"
    echo "Script removed from $HOOK_DIR/$SCRIPT_NAME"
else
    echo "Script not found at $HOOK_DIR/$SCRIPT_NAME — nothing to remove."
fi

echo ""
echo "=== Uninstall complete ==="
echo "Restart Claude Code to apply changes."
