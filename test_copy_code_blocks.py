"""Tests for copy-code-blocks.py — Claude Code clipboard hook."""

import json
import subprocess
from unittest.mock import MagicMock, call, patch

import pytest

# Import from the script (hyphenated filename requires importlib)
import importlib
import importlib.util
import pathlib

import sys

_spec = importlib.util.spec_from_file_location(
    "copy_code_blocks",
    pathlib.Path(__file__).parent / "copy-code-blocks.py",
)
mod = importlib.util.module_from_spec(_spec)
sys.modules["copy_code_blocks"] = mod
_spec.loader.exec_module(mod)

ClipboardBackend = mod.ClipboardBackend
HISTORY_BACKENDS = mod.HISTORY_BACKENDS
DETECTION_ORDER = mod.DETECTION_ORDER
detect_backend = mod.detect_backend
copy_to_clipboard = mod.copy_to_clipboard
extract_code_blocks = mod.extract_code_blocks
main = mod.main


# ---------------------------------------------------------------------------
# extract_code_blocks
# ---------------------------------------------------------------------------
class TestExtractCodeBlocks:
    def test_single_block(self):
        text = "Some text\n```\nprint('hello')\n```\nMore text"
        assert extract_code_blocks(text) == ["print('hello')\n"]

    def test_multiple_blocks(self):
        text = "```\nfirst\n```\nmiddle\n```\nsecond\n```"
        assert extract_code_blocks(text) == ["first\n", "second\n"]

    def test_block_with_language_tag(self):
        text = "```python\nx = 1\n```"
        assert extract_code_blocks(text) == ["x = 1\n"]

    def test_block_with_language_and_attributes(self):
        text = '```python title="example"\nx = 1\n```'
        assert extract_code_blocks(text) == ["x = 1\n"]

    def test_block_with_complex_attributes(self):
        text = '```js highlight={1,3} showLineNumbers\nconst x = 1;\n```'
        assert extract_code_blocks(text) == ["const x = 1;\n"]

    def test_block_with_various_languages(self):
        text = "```bash\necho hi\n```\n```json\n{}\n```\n```rust\nfn main() {}\n```"
        assert extract_code_blocks(text) == [
            "echo hi\n",
            "{}\n",
            "fn main() {}\n",
        ]

    def test_empty_input(self):
        assert extract_code_blocks("") == []

    def test_no_code_blocks(self):
        assert extract_code_blocks("Just plain text, nothing here.") == []

    def test_inline_code_ignored(self):
        assert extract_code_blocks("Use `print()` to print.") == []

    def test_multiline_block(self):
        text = "```\nline1\nline2\nline3\n```"
        assert extract_code_blocks(text) == ["line1\nline2\nline3\n"]

    def test_four_backtick_fence(self):
        text = "````\ninner\n````"
        assert extract_code_blocks(text) == ["inner\n"]

    def test_block_with_empty_content(self):
        text = "```\n\n```"
        assert extract_code_blocks(text) == ["\n"]

    def test_block_preserves_indentation(self):
        text = "```\n    indented\n        more\n```"
        assert extract_code_blocks(text) == ["    indented\n        more\n"]

    def test_block_with_backticks_inside(self):
        """A 4-backtick fence can contain 3-backtick lines inside."""
        text = "````\nsome\n```\nnested\n```\nmore\n````"
        result = extract_code_blocks(text)
        assert len(result) == 1
        assert "nested" in result[0]


# ---------------------------------------------------------------------------
# detect_backend
# ---------------------------------------------------------------------------
class TestDetectBackend:
    def test_no_backend_available(self):
        with patch("shutil.which", return_value=None):
            assert detect_backend() is None

    def test_copyq_preferred_first(self):
        """copyq should be detected first when available."""
        with patch("shutil.which", side_effect=lambda cmd: "/usr/bin/copyq" if cmd == "copyq" else None):
            assert detect_backend() == ClipboardBackend.COPYQ

    def test_xclip_when_no_copyq(self):
        available = {"xclip"}
        with patch("shutil.which", side_effect=lambda cmd: f"/usr/bin/{cmd}" if cmd in available else None):
            assert detect_backend() == ClipboardBackend.XCLIP

    def test_pbcopy_on_macos(self):
        available = {"pbcopy"}
        with patch("shutil.which", side_effect=lambda cmd: f"/usr/bin/{cmd}" if cmd in available else None):
            assert detect_backend() == ClipboardBackend.PBCOPY

    def test_wl_copy_on_wayland(self):
        available = {"wl-copy"}
        with patch("shutil.which", side_effect=lambda cmd: f"/usr/bin/{cmd}" if cmd in available else None):
            assert detect_backend() == ClipboardBackend.WL_COPY

    def test_detection_order_respected(self):
        """When multiple backends exist, the first in DETECTION_ORDER wins."""
        available = {"xclip", "xsel", "pbcopy"}
        with patch("shutil.which", side_effect=lambda cmd: f"/usr/bin/{cmd}" if cmd in available else None):
            result = detect_backend()
            # pbcopy comes before xclip/xsel in DETECTION_ORDER
            assert result == ClipboardBackend.PBCOPY

    def test_wsl_backends(self):
        available = {"clip.exe"}
        with patch("shutil.which", side_effect=lambda cmd: f"/mnt/c/{cmd}" if cmd in available else None):
            assert detect_backend() == ClipboardBackend.CLIP_EXE


# ---------------------------------------------------------------------------
# copy_to_clipboard
# ---------------------------------------------------------------------------
class TestCopyToClipboard:
    @patch(f"{mod.__name__}.subprocess.run")
    def test_copyq(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.COPYQ)
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args == ["copyq", "add", "--", "hello"]

    @patch(f"{mod.__name__}.subprocess.run")
    def test_xclip(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.XCLIP)
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args == ["xclip", "-selection", "clipboard"]
        assert mock_run.call_args[1]["input"] == b"hello"

    @patch(f"{mod.__name__}.subprocess.run")
    def test_xsel(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.XSEL)
        args = mock_run.call_args[0][0]
        assert args == ["xsel", "--clipboard", "--input"]
        assert mock_run.call_args[1]["input"] == b"hello"

    @patch(f"{mod.__name__}.subprocess.run")
    def test_wl_copy(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.WL_COPY)
        args = mock_run.call_args[0][0]
        assert args == ["wl-copy", "--", "hello"]

    @patch(f"{mod.__name__}.subprocess.run")
    def test_pbcopy(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.PBCOPY)
        args = mock_run.call_args[0][0]
        assert args == ["pbcopy"]
        assert mock_run.call_args[1]["input"] == b"hello"

    @patch(f"{mod.__name__}.subprocess.run")
    def test_clip_exe_utf16(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.CLIP_EXE)
        args = mock_run.call_args[0][0]
        assert args == ["clip.exe"]
        assert mock_run.call_args[1]["input"] == "hello".encode("utf-16-le")

    @patch(f"{mod.__name__}.subprocess.run")
    def test_powershell(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.POWERSHELL)
        args = mock_run.call_args[0][0]
        assert "powershell.exe" in args
        assert "hello" in args

    @patch(f"{mod.__name__}.subprocess.run")
    def test_win32yank(self, mock_run):
        copy_to_clipboard("hello", ClipboardBackend.WIN32YANK)
        args = mock_run.call_args[0][0]
        assert args == ["win32yank", "-i", "--crlf"]
        assert mock_run.call_args[1]["input"] == b"hello"

    @patch(f"{mod.__name__}.subprocess.run")
    def test_timeout_is_set(self, mock_run):
        """All backends should have a timeout to avoid hanging."""
        copy_to_clipboard("x", ClipboardBackend.XCLIP)
        assert mock_run.call_args[1]["timeout"] == 5

    @patch(f"{mod.__name__}.subprocess.run")
    def test_check_false(self, mock_run):
        """Subprocess errors should not raise (check=False)."""
        copy_to_clipboard("x", ClipboardBackend.XCLIP)
        assert mock_run.call_args[1]["check"] is False


# ---------------------------------------------------------------------------
# main (integration)
# ---------------------------------------------------------------------------
class TestMain:
    def _make_stdin(self, data: dict) -> MagicMock:
        """Create a mock stdin that json.load can read."""
        mock = MagicMock()
        mock.read.return_value = json.dumps(data)
        return mock

    @patch(f"{mod.__name__}.copy_to_clipboard")
    @patch(f"{mod.__name__}.detect_backend", return_value=ClipboardBackend.XCLIP)
    def test_single_block_copied(self, mock_detect, mock_copy):
        payload = {"last_assistant_message": "Here:\n```\necho hello\n```\n"}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        mock_copy.assert_called_once_with("echo hello", ClipboardBackend.XCLIP)

    @patch(f"{mod.__name__}.copy_to_clipboard")
    @patch(f"{mod.__name__}.detect_backend", return_value=ClipboardBackend.XCLIP)
    def test_multiple_blocks_joined_for_simple_backend(self, mock_detect, mock_copy):
        payload = {"last_assistant_message": "```\nfirst\n```\n```\nsecond\n```"}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        mock_copy.assert_called_once()
        copied_text = mock_copy.call_args[0][0]
        assert "first" in copied_text
        assert "second" in copied_text
        assert "\n\n" in copied_text

    @patch(f"{mod.__name__}.copy_to_clipboard")
    @patch(f"{mod.__name__}.detect_backend", return_value=ClipboardBackend.COPYQ)
    def test_multiple_blocks_separate_for_history_backend(self, mock_detect, mock_copy):
        payload = {"last_assistant_message": "```\nfirst\n```\n```\nsecond\n```"}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        # copyq: each block separate, reversed order (first block = newest in clipboard)
        assert mock_copy.call_count == 2
        calls = [c[0][0] for c in mock_copy.call_args_list]
        assert calls == ["second", "first"]

    @patch(f"{mod.__name__}.copy_to_clipboard")
    @patch(f"{mod.__name__}.detect_backend", return_value=ClipboardBackend.XCLIP)
    def test_no_message_does_nothing(self, mock_detect, mock_copy):
        payload = {"last_assistant_message": ""}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        mock_copy.assert_not_called()

    @patch(f"{mod.__name__}.copy_to_clipboard")
    @patch(f"{mod.__name__}.detect_backend", return_value=ClipboardBackend.XCLIP)
    def test_no_code_blocks_does_nothing(self, mock_detect, mock_copy):
        payload = {"last_assistant_message": "Just some text, no code."}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        mock_copy.assert_not_called()

    @patch(f"{mod.__name__}.copy_to_clipboard")
    @patch(f"{mod.__name__}.detect_backend", return_value=None)
    def test_no_backend_does_nothing(self, mock_detect, mock_copy):
        payload = {"last_assistant_message": "```\ncode\n```"}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        mock_copy.assert_not_called()

    @patch(f"{mod.__name__}.copy_to_clipboard")
    def test_invalid_json_does_nothing(self, mock_copy):
        with patch(f"{mod.__name__}.sys.stdin", MagicMock(read=lambda: "NOT JSON{")):
            main()
        mock_copy.assert_not_called()

    @patch(f"{mod.__name__}.copy_to_clipboard")
    def test_missing_key_does_nothing(self, mock_copy):
        payload = {"some_other_key": "value"}
        with patch(f"{mod.__name__}.sys.stdin", _FakeStdin(payload)):
            main()
        mock_copy.assert_not_called()


class _FakeStdin:
    """Minimal file-like object that json.load() can consume."""

    def __init__(self, data: dict):
        self._data = json.dumps(data)
        self._pos = 0

    def read(self, n=-1):
        if n == -1:
            result = self._data[self._pos:]
            self._pos = len(self._data)
            return result
        result = self._data[self._pos:self._pos + n]
        self._pos += n
        return result
