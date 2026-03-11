# claude-code-clipboard

Claude Code Stop hook that auto-copies fenced code blocks from assistant responses to the system clipboard.

## Project structure

```
copy-code-blocks.py          # Main hook script (runs via stdin JSON from Claude Code)
test_copy_code_blocks.py     # Tests (pytest)
install.sh                   # Installer (copies script + registers hook in settings.json)
uninstall.sh                 # Uninstaller (reverse of install.sh)
```

## Tech stack

- Python 3.10+ (match/case syntax) — zero external dependencies, stdlib only
- pytest for tests

## Running tests

```bash
python3 -m pytest test_copy_code_blocks.py -v
```

## Conventions

- Code, comments, commit messages, variable names — English
- Conventional Commits: `feat:`, `fix:`, `test:`, `chore:`, `refactor:`, `docs:`
- No external dependencies — the hook must run on any system with Python 3.10+ and a clipboard tool
- All clipboard backends must have `timeout=5` and `check=False` on subprocess calls
- The script reads JSON from stdin (`last_assistant_message` key) — this is the Claude Code hook contract

## Manual testing

Test the hook without restarting Claude Code:

```bash
echo '{"last_assistant_message":"```bash\necho hello\n```"}' | python3 copy-code-blocks.py
```

If your clipboard backend works, the code block content should appear in your clipboard.

## Adding a new clipboard backend

Update these 4 places:

1. `ClipboardBackend` enum — add new member
2. `DETECTION_ORDER` list — insert at appropriate priority position
3. `copy_to_clipboard()` — add `case` branch with `timeout=5` and `check=False`
4. `test_copy_code_blocks.py` — add test in `TestCopyToClipboard`

If the backend supports clipboard history, also add it to `HISTORY_BACKENDS`.

## Known limitations

- `clip.exe` (WSL) uses UTF-16LE encoding which may cause issues with some non-ASCII characters
