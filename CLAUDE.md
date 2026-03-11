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

## Known limitations

- Regex doesn't handle nested fences (4-backtick block containing 3-backtick lines) — documented as xfail in tests
- `clip.exe` (WSL) uses UTF-16LE encoding which may cause issues with some non-ASCII characters
