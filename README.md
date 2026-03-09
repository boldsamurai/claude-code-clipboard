# claude-code-clipboard

Automatically copies fenced code blocks from Claude Code responses to your system clipboard — no more broken indentation from manual terminal copy-paste.

## How it works

A [Stop hook](https://docs.claude.ai/en/docs/hooks) runs after every Claude response. It parses the raw Markdown, extracts all fenced code blocks, and adds each one to your clipboard.

```
Claude finishes responding
        │
        ▼
  Stop hook fires
        │
        ▼
  Python script reads
  raw Markdown from stdin
        │
        ▼
  Regex extracts code blocks
        │
        ▼
  Each block → clipboard
```

### Why not just copy from the terminal?

When you select text in a terminal, you copy the **rendered** output — including UI padding, soft wraps, and line numbers. This hook operates on the **raw Markdown** before rendering, so you get clean, correctly formatted code every time.

## Supported clipboard tools

| Tool | Platform | Multiple entries |
|------|----------|-----------------|
| [copyq](https://hluk.github.io/CopyQ/) | Linux / macOS / Windows | Yes — each block is a separate history entry |
| xclip | Linux (X11) | No — all blocks joined into one |
| xsel | Linux (X11) | No — all blocks joined into one |
| wl-copy | Linux (Wayland) | No — all blocks joined into one |
| pbcopy | macOS | No — all blocks joined into one |
| clip.exe | Windows (WSL) | No — all blocks joined into one |
| powershell.exe | Windows (WSL) | No — all blocks joined into one |
| win32yank | Windows / WSL | No — all blocks joined into one |

For the best experience, use **copyq** or another clipboard manager with history — you'll get each code block as a separate entry you can pick from.

### Windows / WSL

Claude Code on Windows runs inside WSL. The hook auto-detects `clip.exe` (built into WSL) to copy directly to the Windows clipboard. No extra installation needed — it just works.

## Requirements

- [Claude Code](https://docs.claude.ai) CLI
- Python 3.10+
- One of the supported clipboard tools

## Install

```bash
git clone https://github.com/boldsamurai/claude-code-clipboard.git
cd claude-code-clipboard
bash install.sh
```

Then restart Claude Code.

## Uninstall

```bash
cd claude-code-clipboard
bash uninstall.sh
```

Then restart Claude Code.

## Limitations

- **Single-entry backends** (`xclip`, `pbcopy`, `clip.exe`, etc.) don't support clipboard history. When a response contains multiple code blocks, they get joined into a single clipboard entry separated by blank lines. To get each block as a separate entry you can pick from, install [copyq](https://hluk.github.io/CopyQ/) — it works on Linux, macOS, and Windows.
- **`clip.exe`** (WSL) converts text to UTF-16LE, which is what Windows expects. In rare cases with non-ASCII characters, encoding issues may occur.
- The hook fires on **every** Claude response, even if you don't need the code blocks. This is invisible in practice — the script runs in ~50ms and doesn't block Claude.
- Only **fenced** code blocks (`` ``` ``) are extracted. Inline code (`` `like this` ``) is ignored by design — it's typically not something you'd paste into a terminal.

## What gets installed

- `~/.claude/hooks/copy-code-blocks.py` — the hook script
- A `Stop` hook entry in `~/.claude/settings.json`

No other files are modified. No dependencies beyond Python stdlib.

## License

MIT
