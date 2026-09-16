#!/usr/bin/env python3
"""Builds Tetris-Architektur-Dossier.html — a single, self-contained file
(all assets/ images inlined as base64 data URIs) from index.html.

Why: the hosted Claude Artifact version of this page lives inside a
sandboxed iframe that blocks both window.print() (no "allow-modals") and any
script-driven download (no "allow-downloads") — so there's no way to export
a PDF from inside it, and printing it via the browser's own Ctrl/Cmd+P
doesn't reliably apply the page's own @media print rules either. Opening
this standalone file directly (a plain local file, no iframe involved) does
not have either restriction — Ctrl/Cmd+P there applies the print stylesheet
normally, with correct page breaks. See the project CLAUDE.md and the
global Godot-projects CLAUDE.md (same pattern as the sister Galaga dossier)
for the fuller story.

Run from this directory: python3 build_standalone.py
"""

import base64
import mimetypes
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "index.html"
OUT = HERE / "Tetris-Architektur-Dossier.html"

IMG_SRC_RE = re.compile(r'src="(assets/[^"]+)"')


def inline_images(html: str) -> str:
    def replace(match: "re.Match[str]") -> str:
        rel_path = match.group(1)
        img_path = HERE / rel_path
        mime, _ = mimetypes.guess_type(img_path.name)
        data = base64.b64encode(img_path.read_bytes()).decode("ascii")
        return f'src="data:{mime};base64,{data}"'

    return IMG_SRC_RE.sub(replace, html)


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    html = inline_images(html)

    standalone = (
        "<!doctype html>\n"
        '<html lang="de">\n'
        "<head>\n"
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        + html
        + "\n</body>\n</html>\n"
    )

    OUT.write_text(standalone, encoding="utf-8")
    size_mb = OUT.stat().st_size / 1024 / 1024
    print(f"wrote {OUT.name} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()
