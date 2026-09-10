#!/usr/bin/env python3
"""Build herdr.ico for the sheepdock Windows launcher.

Takes the herdr ram-head logo and writes a multi-size .ico with every size the
Windows shell asks for: 16 px for the title bar, 24/32 for the taskbar, 48/256
for Explorer and Alt-Tab. Windows icons are square, so unlike the macOS
variant no mask is applied.

Pillow is required for the resize; without it the script exits with code 3 so
install.ps1 can try `uv run --with pillow` or fall back to herdr.dev's favicon.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

DEFAULT_SOURCE = "https://herdr.dev/assets/logo.png"
DEFAULT_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
EXIT_NO_PILLOW = 3

# Some CDNs answer 403 to urllib's default User-Agent, so present a real one.
USER_AGENT = "sheepdock (+https://github.com/ralfkuh-lab/sheepdock)"


def fetch(source: str, dest: Path) -> Path:
    if "://" in source:
        print(f"  fetching {source}")
        request = urllib.request.Request(source, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=30) as r, dest.open("wb") as f:
                shutil.copyfileobj(r, f)
        except Exception as exc:
            if shutil.which("curl") is None:
                sys.exit(f"error: could not download {source}: {exc}")
            print(f"  urllib failed ({exc}) - retrying with curl")
            subprocess.run(["curl", "-fsSL", "-A", USER_AGENT, source, "-o", str(dest)],
                           check=True)
    else:
        src = Path(source).expanduser()
        if not src.is_file():
            sys.exit(f"error: no such file: {src}")
        shutil.copyfile(src, dest)
    return dest


def build_ico(src: Path, out: Path, sizes: tuple[int, ...]) -> None:
    try:
        from PIL import Image
    except ImportError:
        print("  Pillow is not installed - cannot build the .ico", file=sys.stderr)
        print("  install it with:  python -m pip install --user pillow", file=sys.stderr)
        sys.exit(EXIT_NO_PILLOW)

    img = Image.open(src).convert("RGBA")
    if img.width != img.height:
        side = min(img.size)
        left = (img.width - side) // 2
        top = (img.height - side) // 2
        img = img.crop((left, top, left + side, top + side))
    out.parent.mkdir(parents=True, exist_ok=True)
    # Pillow resizes from the largest frame itself; passing an RGBA master keeps
    # antialiased edges in the small sizes.
    img.save(out, format="ICO", sizes=[(s, s) for s in sizes])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SOURCE,
                    help=f"logo URL or local image path (default: {DEFAULT_SOURCE})")
    ap.add_argument("--out", default="build/herdr.ico", help="output .ico path")
    ap.add_argument("--sizes", default=",".join(map(str, DEFAULT_SIZES)),
                    help="comma-separated pixel sizes to embed")
    args = ap.parse_args()

    sizes = tuple(int(s) for s in args.sizes.split(",") if s.strip())
    out = Path(args.out).expanduser()
    with tempfile.TemporaryDirectory() as tmp:
        raw = fetch(args.source, Path(tmp) / "logo.png")
        build_ico(raw, out, sizes)
    print(f"  wrote {out} ({len(sizes)} sizes)")


if __name__ == "__main__":
    main()
