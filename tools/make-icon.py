#!/usr/bin/env python3
"""Build herdr.icns for the sheepdock launcher.

Takes the herdr ram-head logo, fits it to Apple's icon grid (an 824x824 body on
a 1024x1024 canvas) behind a squircle mask, and compiles every size macOS wants
into a single .icns via iconutil.

Pillow is optional. Without it the logo is used as-is, which gives a square
icon that looks slightly foreign next to other Dock icons but works fine.
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
CANVAS, BODY = 1024, 824          # Apple's macOS icon grid
SQUIRCLE_N = 5.0                  # |x|^n + |y|^n = 1 approximates continuous corners
ICNS_SIZES = (16, 32, 128, 256, 512)


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
            print(f"  urllib failed ({exc}) — retrying with curl")
            subprocess.run(["curl", "-fsSL", "-A", USER_AGENT, source, "-o", str(dest)],
                           check=True)
    else:
        src = Path(source).expanduser()
        if not src.is_file():
            sys.exit(f"error: no such file: {src}")
        shutil.copyfile(src, dest)
    return dest


def squircle_mask(size: int, supersample: int = 4):
    """A filled superellipse, antialiased by drawing large and scaling down."""
    from PIL import Image, ImageDraw

    r = size * supersample // 2
    mask = Image.new("L", (r * 2, r * 2), 0)
    draw = ImageDraw.Draw(mask)
    for y in range(r):
        half = int(((1.0 - (y / r) ** SQUIRCLE_N) ** (1.0 / SQUIRCLE_N)) * r)
        for row in (r - 1 - y, r + y):
            draw.line([(r - half, row), (r + half - 1, row)], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def build_master(src: Path, dest: Path, mask: bool) -> None:
    try:
        from PIL import Image
    except ImportError:
        if mask:
            print("  Pillow not installed — using the logo unmasked (square corners).")
            print("  For the rounded macOS look: pip3 install Pillow")
        shutil.copyfile(src, dest)
        return

    logo = Image.open(src).convert("RGB").resize((BODY, BODY), Image.LANCZOS)
    body = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 0))
    body.paste(logo, (0, 0), squircle_mask(BODY) if mask else None)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - BODY) // 2
    canvas.paste(body, (offset, offset), body)
    canvas.save(dest)


def build_icns(master: Path, out: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "herdr.iconset"
        iconset.mkdir()
        try:
            from PIL import Image

            img = Image.open(master).convert("RGBA")
            for base in ICNS_SIZES:
                for name, px in ((f"{base}x{base}", base), (f"{base}x{base}@2x", base * 2)):
                    img.resize((px, px), Image.LANCZOS).save(iconset / f"icon_{name}.png")
        except ImportError:
            for base in ICNS_SIZES:
                for name, px in ((f"{base}x{base}", base), (f"{base}x{base}@2x", base * 2)):
                    subprocess.run(
                        ["sips", "-s", "format", "png", "-z", str(px), str(px),
                         str(master), "--out", str(iconset / f"icon_{name}.png")],
                        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SOURCE,
                    help=f"logo URL or local image path (default: {DEFAULT_SOURCE})")
    ap.add_argument("--out", default="build/herdr.icns", help="output .icns path")
    ap.add_argument("--no-mask", action="store_true",
                    help="skip the squircle mask and keep the logo square")
    args = ap.parse_args()

    out = Path(args.out).expanduser()
    with tempfile.TemporaryDirectory() as tmp:
        raw = fetch(args.source, Path(tmp) / "logo.png")
        master = Path(tmp) / "master.png"
        build_master(raw, master, mask=not args.no_mask)
        build_icns(master, out)
    print(f"  wrote {out}")


if __name__ == "__main__":
    main()
