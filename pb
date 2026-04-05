#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["coolname", "Pillow"]
# ///

# ABOUTME: shared clipboard tool with file-backed history, works in pipelines
# ABOUTME: use 'pb copy' to save, 'pb paste' to load, 'pb list' to browse with fzf

import argparse
import base64
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

DEFAULT_PB_DIR = Path.home() / "Library" / "CloudStorage" / "Dropbox" / "pb"
PB_DIR = Path(os.environ.get("PB_DIR", DEFAULT_PB_DIR))
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".tiff", ".gif"}
TEXT_EXTENSIONS = {".txt"}
# Matches our naming convention: 2026-04-02T17-05-23_cool-slug.ext
ENTRY_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}_.+\.\w+$")


def generate_filename(ext):
    """Generate a unique filename with timestamp and coolname slug."""
    import coolname

    ts = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    slug = coolname.generate_slug(2)
    return f"{ts}_{slug}{ext}"


def get_clipboard_type():
    """Detect what type of data is on the system clipboard."""
    result = subprocess.run(
        ["osascript", "-e", "clipboard info"],
        capture_output=True, text=True,
    )
    info = result.stdout
    if "PNGf" in info or "TIFF" in info or "JPEG" in info:
        return "image"
    if "utf8" in info or "ut16" in info or "string" in info:
        return "text"
    return "text"


def save_clipboard_image(dest):
    """Extract image from clipboard and save as PNG."""
    from PIL import Image

    # Try PNG first, then TIFF (macOS screenshots use TIFF internally)
    for cls in ["PNGf", "TIFF", "JPEG"]:
        script = f'''
            try
                set imgData to (the clipboard as \u00abclass {cls}\u00bb)
                set filePath to POSIX file "{dest}"
                set fileRef to open for access filePath with write permission
                write imgData to fileRef
                close access fileRef
                return "ok"
            on error
                return "fail"
            end try
        '''
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True,
        )
        if result.stdout.strip() == "ok":
            # Convert to PNG if not already
            if cls != "PNGf" and dest.suffix == ".png":
                img = Image.open(dest)
                img.save(dest, "PNG")
            return True
    return False


def load_clipboard_image(path):
    """Load an image file into the system clipboard."""
    # Convert to PNG if needed
    png_path = path
    if path.suffix.lower() not in (".png",):
        from PIL import Image
        import tempfile

        img = Image.open(path)
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        img.save(tmp.name, "PNG")
        png_path = Path(tmp.name)

    script = f'''
        set the clipboard to (read POSIX file "{png_path}" as \u00abclass PNGf\u00bb)
    '''
    subprocess.run(["osascript", "-e", script], check=True)

    if png_path != path:
        png_path.unlink()


def display_image_kitty(path):
    """Display an image in the terminal using the Kitty graphics protocol."""
    from PIL import Image
    import io

    # Convert to PNG if not already
    img = Image.open(path)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    raw = buf.getvalue()

    data = base64.b64encode(raw).decode()
    first = True
    while data:
        chunk = data[:4096]
        data = data[4096:]
        m = 1 if data else 0
        if first:
            sys.stdout.write(f"\033_Ga=T,f=100,m={m};{chunk}\033\\")
            first = False
        else:
            sys.stdout.write(f"\033_Gm={m};{chunk}\033\\")
    sys.stdout.write("\n")
    sys.stdout.flush()


def list_entries():
    """Return clipboard entries sorted newest first."""
    if not PB_DIR.exists():
        return []
    entries = [
        f for f in PB_DIR.iterdir()
        if f.is_file() and f.suffix in IMAGE_EXTENSIONS | TEXT_EXTENSIONS
        and ENTRY_PATTERN.match(f.name)
    ]
    entries.sort(key=lambda f: f.name, reverse=True)
    return entries


def find_entry(name):
    """Find a clipboard entry by partial name match."""
    entries = list_entries()
    matches = [e for e in entries if name in e.name]
    if not matches:
        print(f"No entry matching '{name}'", file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        print(f"Multiple matches for '{name}':", file=sys.stderr)
        for m in matches:
            print(f"  {m.name}", file=sys.stderr)
        sys.exit(1)
    return matches[0]


def output_entry(entry):
    """Output an entry: to stdout if piped, to system clipboard if interactive."""
    if not sys.stdout.isatty():
        # Pipeline mode: write contents to stdout
        if entry.suffix in IMAGE_EXTENSIONS:
            sys.stdout.buffer.write(entry.read_bytes())
        else:
            sys.stdout.write(entry.read_text())
    else:
        # Interactive: load into system clipboard
        if entry.suffix in IMAGE_EXTENSIONS:
            load_clipboard_image(entry)
        else:
            subprocess.run(["pbcopy"], input=entry.read_text(), text=True)
        print(entry.name, file=sys.stderr)


def cmd_copy(args):
    """Capture text or image to a file in PB_DIR."""
    if not sys.stdin.isatty():
        # Piped input: echo "hello" | pb copy  OR  cat img.png | pb copy
        data = sys.stdin.buffer.read()
        if not data:
            print("No input from pipe", file=sys.stderr)
            sys.exit(1)
        if data[:8] == b'\x89PNG\r\n\x1a\n':
            ext = ".png"
        elif data[:3] == b'\xff\xd8\xff':
            ext = ".jpg"
        elif data[:4] in (b'GIF8',):
            ext = ".gif"
        elif data[:4] in (b'II\x2a\x00', b'MM\x00\x2a'):
            ext = ".tiff"
        else:
            ext = ".txt"
        filename = generate_filename(ext)
        dest = PB_DIR / filename
        dest.write_bytes(data)
        print(dest.name, file=sys.stderr)
        sys.stdout.buffer.write(data)
        return

    # Interactive: read from system clipboard
    clip_type = get_clipboard_type()
    if clip_type == "image":
        filename = generate_filename(".png")
        dest = PB_DIR / filename
        if save_clipboard_image(dest):
            print(dest.name, file=sys.stderr)
            sys.stdout.buffer.write(dest.read_bytes())
        else:
            print("Failed to capture image from clipboard", file=sys.stderr)
            sys.exit(1)
    else:
        result = subprocess.run(["pbpaste"], capture_output=True, text=True)
        text = result.stdout
        if not text:
            print("Clipboard is empty", file=sys.stderr)
            sys.exit(1)
        filename = generate_filename(".txt")
        dest = PB_DIR / filename
        dest.write_text(text)
        print(dest.name, file=sys.stderr)
        sys.stdout.write(text)


def cmd_paste(args):
    """Load a clipboard entry into the system clipboard or stdout."""
    if args.name:
        entry = find_entry(args.name)
    else:
        entries = list_entries()
        if not entries:
            print("No clipboard entries", file=sys.stderr)
            sys.exit(1)
        entry = entries[0]

    output_entry(entry)


def cmd_list(args):
    """Browse clipboard entries with fzf preview."""
    entries = list_entries()
    if not entries:
        print("No clipboard entries", file=sys.stderr)
        sys.exit(1)

    names = "\n".join(e.name for e in entries)
    # pb-preview is a plain python3 script (no uv) for fast fzf preview
    preview_script = Path(__file__).resolve().parent / "pb-preview"
    preview_cmd = f'{preview_script} {PB_DIR}/{{}}'

    # Scroll current content into scrollback so fzf renders cleanly with Kitty graphics
    rows = os.get_terminal_size().lines
    sys.stdout.write("\n" * rows + "\033[H")
    sys.stdout.flush()

    try:
        result = subprocess.run(
            ["fzf", "--preview", preview_cmd, "--preview-window=right:60%"],
            input=names, text=True, stdout=subprocess.PIPE,
        )
    except FileNotFoundError:
        print("fzf is required for pb list (brew install fzf)", file=sys.stderr)
        sys.exit(1)
    finally:
        # Clear any Kitty graphics left on screen by the preview
        sys.stdout.write("\033_Ga=d\033\\")
        sys.stdout.flush()

    selected = result.stdout.strip()
    if selected:
        output_entry(PB_DIR / selected)


def cmd_clean(args):
    """Remove clipboard entries older than N days."""
    cutoff = datetime.now() - timedelta(days=args.older_than)
    entries = list_entries()
    removed = 0
    for entry in entries:
        # Parse timestamp from filename: 2026-04-02T17-05-23_slug.ext
        try:
            ts_str = entry.stem.split("_")[0]
            ts = datetime.strptime(ts_str, "%Y-%m-%dT%H-%M-%S")
        except (ValueError, IndexError):
            continue
        if ts < cutoff:
            print(f"  {entry.name}", file=sys.stderr)
            entry.unlink()
            removed += 1
    print(f"Removed {removed} entries", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        prog="pb",
        description="""\
Shared clipboard with file-backed history.

Saves clipboard entries (text and images) to a directory that can be
synced between machines. Works both interactively and in pipelines.

Interactive usage:
  pb copy              Save system clipboard to a file
  pb paste             Load most recent entry into system clipboard
  pb paste foo         Load entry matching "foo" into clipboard
  pb list              Browse entries with fzf preview, paste selection

Pipeline usage:
  echo "hi" | pb copy  Save piped text to a file
  pb paste | grep foo  Output most recent entry to stdout
  pb paste > out.txt   Redirect entry contents to a file
  pb list | wc -l      Browse with fzf, pipe selected entry to stdout

Housekeeping:
  pb clean --older-than 30  Remove entries older than 30 days

Environment:
  PB_DIR    Storage directory (default: ~/Library/CloudStorage/Dropbox/pb)""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("copy", help="Save clipboard or piped stdin to a file")

    paste_parser = sub.add_parser("paste",
        help="Load entry into clipboard (interactive) or stdout (piped)")
    paste_parser.add_argument("name", nargs="?",
        help="Partial name to match (default: most recent)")

    sub.add_parser("list",
        help="Browse entries with fzf, paste or pipe selection")

    clean_parser = sub.add_parser("clean", help="Remove old entries")
    clean_parser.add_argument("--older-than", type=int, required=True,
                              help="Remove entries older than N days")

    args = parser.parse_args()

    if not PB_DIR.exists():
        print(
            f"Directory does not exist: {PB_DIR}\n"
            f"Create it with: mkdir -p '{PB_DIR}'\n"
            f"Or set PB_DIR to use a different location.",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.command == "copy":
        cmd_copy(args)
    elif args.command == "paste":
        cmd_paste(args)
    elif args.command == "list":
        cmd_list(args)
    elif args.command == "clean":
        cmd_clean(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
