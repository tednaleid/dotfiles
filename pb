#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["coolname", "Pillow", "rich", "watchdog"]
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
# Matches naming convention (millis optional for backward compat):
#   2026-04-02T17-05-23_slug.ext         (legacy, second precision)
#   2026-04-02T17-05-23.456_slug.ext     (new, millisecond precision)
ENTRY_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:\.\d{3})?_.+\.\w+$")


def generate_filename(ext):
    """Generate a unique filename with ms-precision timestamp and coolname slug."""
    import coolname

    now = datetime.now()
    ts = now.strftime("%Y-%m-%dT%H-%M-%S") + f".{now.microsecond // 1000:03d}"
    slug = coolname.generate_slug(2)
    return f"{ts}_{slug}{ext}"


def parse_entry_timestamp(name):
    """Parse datetime from a pb entry filename. Handles legacy and ms formats."""
    ts_str = name.split("_")[0]
    for fmt in ("%Y-%m-%dT%H-%M-%S.%f", "%Y-%m-%dT%H-%M-%S"):
        try:
            return datetime.strptime(ts_str, fmt)
        except ValueError:
            continue
    return None


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


def cmd_preview(args):
    """Preview a clipboard entry (used internally by fzf)."""
    path = Path(args.file)
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    # Clear any previous Kitty graphics before rendering new content
    sys.stdout.write("\033_Ga=d\033\\")
    sys.stdout.flush()

    if path.suffix.lower() in IMAGE_EXTENSIONS:
        display_image_kitty(path)
    else:
        lines = path.read_text().splitlines()[:100]
        print("\n".join(lines))


def cmd_list(args):
    """Browse clipboard entries with fzf preview."""
    entries = list_entries()
    if not entries:
        print("No clipboard entries", file=sys.stderr)
        sys.exit(1)

    names = "\n".join(e.name for e in entries)
    pb_script = Path(__file__).resolve()
    preview_cmd = f'{pb_script} preview {PB_DIR}/{{}}'

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
        ts = parse_entry_timestamp(entry.name)
        if ts is None:
            continue
        if ts < cutoff:
            print(f"  {entry.name}", file=sys.stderr)
            entry.unlink()
            removed += 1
    print(f"Removed {removed} entries", file=sys.stderr)


SIZE_BUCKETS = [
    ("tiny",   0,                 1024),
    ("small",  1024,              100 * 1024),
    ("medium", 100 * 1024,        1024 * 1024),
    ("large",  1024 * 1024,       10 * 1024 * 1024),
    ("huge",   10 * 1024 * 1024,  float("inf")),
]


def bucket_for(size):
    for name, lo, hi in SIZE_BUCKETS:
        if lo <= size < hi:
            return name
    return "huge"


def format_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def cmd_watch(args):
    """Watch PB_DIR for new arrivals with live split-screen view + summary stats."""
    import time
    from collections import deque
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer
    from rich.console import Console
    from rich.layout import Layout
    from rich.live import Live
    from rich.panel import Panel
    from rich.table import Table

    console = Console()
    stats = {name: [] for name, _, _ in SIZE_BUCKETS}
    recent = deque(maxlen=20)
    latest_file = {"path": None, "size": 0}

    class Handler(FileSystemEventHandler):
        def __init__(self):
            super().__init__()
            self.seen = {e.name for e in list_entries()}

        def _process(self, path_str):
            arrival = datetime.now()
            path = Path(path_str)
            if path.name in self.seen:
                return
            if not ENTRY_PATTERN.match(path.name):
                return
            ts = parse_entry_timestamp(path.name)
            if ts is None:
                return
            try:
                size = path.stat().st_size
            except OSError:
                return
            self.seen.add(path.name)
            latency = (arrival - ts).total_seconds()
            legacy = "." not in path.name.split("_")[0]
            bucket = bucket_for(size)
            stats[bucket].append((latency, size, path.name, legacy))
            recent.append((arrival, latency, size, path.name, legacy))
            latest_file["path"] = path
            latest_file["size"] = size

        def on_created(self, event):
            if not event.is_directory:
                self._process(event.src_path)

        def on_moved(self, event):
            if not event.is_directory:
                self._process(event.dest_path)

    def build_log():
        t = Table.grid(padding=(0, 1), expand=True)
        t.add_column("arrival", style="dim", width=12)
        t.add_column("latency", justify="right", width=10)
        t.add_column("size", justify="right", width=10)
        t.add_column("filename", overflow="ellipsis", no_wrap=True)
        t.add_row("arrival", "latency", "size", "filename")
        for arrival, lat, size, name, legacy in recent:
            mark = "[yellow]*[/]" if legacy else ""
            t.add_row(
                arrival.strftime("%H:%M:%S.") + f"{arrival.microsecond//1000:03d}",
                f"[cyan]{lat:.3f}s[/]{mark}",
                f"[magenta]{format_size(size)}[/]",
                name,
            )
        total = sum(len(v) for v in stats.values())
        return Panel(t, title=f"Arrivals ({total} total)", border_style="blue")

    def build_preview():
        path = latest_file["path"]
        if path is None:
            return Panel("[dim]Waiting for first arrival...[/]",
                         title="Latest", border_style="green")
        size_str = format_size(latest_file["size"])
        if path.suffix.lower() in IMAGE_EXTENSIONS:
            body = f"[dim][image: {size_str}][/]"
        else:
            try:
                lines = path.read_text(errors="replace").splitlines()[:15]
                body = "\n".join(lines) if lines else "[dim](empty)[/]"
            except OSError as e:
                body = f"[red]read error: {e}[/]"
        return Panel(body, title=f"Latest: {path.name}", border_style="green")

    layout = Layout()
    layout.split_column(
        Layout(name="log", ratio=2),
        Layout(name="preview", ratio=1),
    )

    observer = Observer()
    observer.schedule(Handler(), str(PB_DIR), recursive=False)
    observer.start()

    console.print(
        f"[dim]pb watch (FSEvents on {PB_DIR}). Ctrl-C for stats.[/]"
    )

    try:
        with Live(layout, console=console, refresh_per_second=10, screen=True):
            while True:
                time.sleep(0.1)
                layout["log"].update(build_log())
                layout["preview"].update(build_preview())
    except KeyboardInterrupt:
        pass
    finally:
        observer.stop()
        observer.join()

    _print_summary(console, stats)


def _print_summary(console, stats):
    from rich.table import Table

    all_lats = [lat for bucket in stats.values() for (lat, *_) in bucket]
    if not all_lats:
        console.print("[dim]No new arrivals observed.[/]")
        return

    overall = Table(title="Overall sync latency", title_style="bold")
    overall.add_column("count", justify="right")
    overall.add_column("min", justify="right", style="green")
    overall.add_column("mean", justify="right", style="cyan")
    overall.add_column("max", justify="right", style="red")
    overall.add_row(
        str(len(all_lats)),
        f"{min(all_lats):.3f}s",
        f"{sum(all_lats)/len(all_lats):.3f}s",
        f"{max(all_lats):.3f}s",
    )
    console.print(overall)

    bybucket = Table(title="By file size", title_style="bold")
    bybucket.add_column("bucket")
    bybucket.add_column("range")
    bybucket.add_column("count", justify="right")
    bybucket.add_column("min", justify="right", style="green")
    bybucket.add_column("mean", justify="right", style="cyan")
    bybucket.add_column("max", justify="right", style="red")
    for name, lo, hi in SIZE_BUCKETS:
        rows = stats[name]
        if not rows:
            continue
        lats = [r[0] for r in rows]
        hi_str = format_size(hi) if hi != float("inf") else "+"
        bybucket.add_row(
            name,
            f"{format_size(lo)} – {hi_str}",
            str(len(rows)),
            f"{min(lats):.3f}s",
            f"{sum(lats)/len(lats):.3f}s",
            f"{max(lats):.3f}s",
        )
    console.print(bybucket)


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

Sync latency testing:
  pb watch                  Watch PB_DIR, report sync latency as files arrive

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

    preview_parser = sub.add_parser("preview",
        help="Preview a file (used internally by fzf)")
    preview_parser.add_argument("file", help="File to preview")

    clean_parser = sub.add_parser("clean", help="Remove old entries")
    clean_parser.add_argument("--older-than", type=int, required=True,
                              help="Remove entries older than N days")

    sub.add_parser("watch",
        help="Watch PB_DIR for new arrivals, measure sync latency")

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
    elif args.command == "preview":
        cmd_preview(args)
    elif args.command == "clean":
        cmd_clean(args)
    elif args.command == "watch":
        cmd_watch(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
