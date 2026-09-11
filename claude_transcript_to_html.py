#!/usr/bin/env python3
"""
claude_transcript_to_html.py
============================

Render a Claude Code session transcript (`*.jsonl`) as a single self-contained
HTML page: speaker-separated, Markdown-formatted, with syntax-highlighted code
blocks and collapsible tool calls / tool results / thinking.

In-page toolbar:
  * Expand / Collapse all tools
  * Reading mode  - hides every tool call, tool result and thinking block (and
                    any Claude turn that was nothing but those), leaving the
                    plain conversation
  * Always show images (checked by default) - a tool result that embedded a
                    real image (e.g. Read on a screenshot) stays visible even
                    with tools collapsed or Reading mode on; click that one
                    image's own header to hide just it (e.g. a blank/unwanted
                    screenshot) without affecting the others; uncheck the box
                    to make images obey the same collapse/reading rules as
                    everything else
  * Show example code (unchecked by default) - Reading mode normally hides
                    every fenced code block Claude writes directly in its own
                    prose (a solution snippet, not a diff or tool output);
                    checking this reveals all of them, or click one such
                    block's own header to reveal just that one
  * Toggle light / dark
  * Export to PDF - opens the browser print dialog ("Save as PDF"); the left
                    table of contents prints as a clickable index and anything
                    hidden or collapsed on screen is left out of the PDF

Transcripts live in:
    ~/.claude/projects/<slugified-project-path>/<session-id>.jsonl

Usage
-----
    python3 claude_transcript_to_html.py TRANSCRIPT.jsonl [-o OUTPUT.html] [options]

    # newest transcript for the current project:
    python3 claude_transcript_to_html.py --latest

Options
-------
    -o, --output PATH     Output file (default: <transcript>.html next to input).
    --latest             Use the most recently modified *.jsonl under
                         ~/.claude/projects/ that matches the current directory.
    --title TEXT         Page title (default: derived from the file name).
    --open               Open the result in the default browser when done.
    --max-result N       Truncate each tool result to N characters (default 20000,
                         0 = unlimited).
    --no-meta            Drop events flagged isMeta (Claude Code's injected notes).
    --light              Force the light colour scheme (default follows the OS).
    --show-ids           Include the source filename and session UUID in the page
                         header, and stop scrubbing that UUID everywhere else it
                         shows up (e.g. this session's scratchpad path). Off by
                         default so a shared/committed export doesn't carry it.
    --keep-diagnostic-commands
                         Don't redact /cost, /usage, /context, /explain-usage etc.
                         turns (see SENSITIVE_COMMANDS) — their output tends to
                         carry session/cost internals rather than project
                         discussion, so it's stripped by default.
    --keep-emails        Don't mask email addresses anywhere on the page. They
                         turn up unpredictably (a `git config` dump, a memory
                         file, a passing remark) rather than in one fixable
                         spot, so every address is masked by default.

Only the Python standard library is required. Syntax highlighting is a
progressive enhancement via highlight.js from a CDN; offline, code blocks simply
render as plain monospace.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import re
import sys
import webbrowser
from pathlib import Path


# --------------------------------------------------------------------------- #
#  transcript loading
# --------------------------------------------------------------------------- #

def load_events(path: Path) -> list[dict]:
    events: list[dict] = []
    with path.open(encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as exc:
                print(f"warn: skipping malformed line {lineno}: {exc}", file=sys.stderr)
    return events


def find_latest_transcript() -> Path | None:
    root = Path.home() / ".claude" / "projects"
    if not root.is_dir():
        return None
    cwd = Path.cwd().resolve()
    # Claude Code slugifies the project path by replacing os.sep with '-'
    slug = "-" + str(cwd).strip(os.sep).replace(os.sep, "-")
    candidates = sorted(root.glob(f"*{slug.split('-')[-1]}*/*.jsonl"),
                        key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        candidates = sorted(root.glob("*/*.jsonl"),
                            key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else None


def fmt_ts(iso: str | None) -> str:
    if not iso:
        return ""
    try:
        t = dt.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        return t.astimezone().strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        return str(iso)


# --------------------------------------------------------------------------- #
#  minimal Markdown -> HTML
# --------------------------------------------------------------------------- #

def _inline(text: str) -> str:
    """Inline Markdown: code, links, bold, italic, strike, bare URLs."""
    s = html.escape(text, quote=False)
    stash: list[str] = []

    def keep(fragment: str) -> str:
        stash.append(fragment)
        return f"\x00{len(stash) - 1}\x00"

    s = re.sub(r"`([^`]+)`", lambda m: keep(f"<code>{m.group(1)}</code>"), s)
    s = re.sub(
        r"\[([^\]]+)\]\(\s*(?:&lt;)?([^)\s]+?)(?:&gt;)?\s*\)",
        lambda m: keep(
            f'<a href="{m.group(2)}" target="_blank" rel="noopener">{m.group(1)}</a>'
        ),
        s,
    )
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"__([^_]+)__", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", s)
    s = re.sub(r"~~([^~]+)~~", r"<del>\1</del>", s)
    # <https://...> autolinks
    s = re.sub(
        r"&lt;(https?://[^\s&]+)&gt;",
        lambda m: keep(
            f'<a href="{m.group(1)}" target="_blank" rel="noopener">{m.group(1)}</a>'
        ),
        s,
    )
    # bare URLs (drop trailing sentence punctuation)
    def _bare(m: re.Match) -> str:
        url = m.group(0).rstrip(".,;:!?)")
        return keep(f'<a href="{url}" target="_blank" rel="noopener">{url}</a>')

    s = re.sub(r"(?<![\"\x00>])\bhttps?://[^\s<>()\x00]+", _bare, s)
    s = re.sub(r"\x00(\d+)\x00", lambda m: stash[int(m.group(1))], s)
    return s


def _split_row(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


_BLOCK_START = re.compile(r"^\s*(```|#{1,6}\s|[-*+]\s|\d+[.)]\s|>)")


def md_to_html(text: str, mark_code: bool = False) -> str:
    """`mark_code` wraps fenced code blocks as a `doc-code` fold — Claude's own
    example/solution snippets written directly in its prose, as opposed to a
    tool diff or tool output. Only meaningful for assistant text (see the
    `mark_code=` call sites in `render_blocks`); see the `doc-code` CSS for
    how "Show example code" / Reading mode use the tag."""
    lines = (text or "").split("\n")
    out: list[str] = []
    i, n = 0, len(lines)

    while i < n:
        line = lines[i]

        m = re.match(r"^\s*```+\s*([\w+#.-]*)", line)
        if m:
            lang = (m.group(1) or "text").lower()
            i += 1
            buf: list[str] = []
            while i < n and not re.match(r"^\s*```+\s*$", lines[i]):
                buf.append(lines[i])
                i += 1
            i += 1
            code = html.escape("\n".join(buf), quote=False)
            pre_html = f'<pre><code class="language-{html.escape(lang)}">{code}</code></pre>'
            if mark_code:
                pre_html = fold("&#128187; example code", pre_html, "doc_code", "doc-code")
            out.append(pre_html)
            continue

        if not line.strip():
            i += 1
            continue

        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            lvl = len(m.group(1))
            out.append(f"<h{lvl}>{_inline(m.group(2).strip())}</h{lvl}>")
            i += 1
            continue

        if re.match(r"^\s*([-*_])(\s*\1){2,}\s*$", line):
            out.append("<hr>")
            i += 1
            continue

        if (
            "|" in line
            and i + 1 < n
            and "-" in lines[i + 1]
            and re.match(r"^\s*\|?[\s:|-]+\|?\s*$", lines[i + 1])
        ):
            header = _split_row(line)
            i += 2
            rows: list[list[str]] = []
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append(_split_row(lines[i]))
                i += 1
            thead = "".join(f"<th>{_inline(c)}</th>" for c in header)
            body = "".join(
                "<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in r) + "</tr>"
                for r in rows
            )
            out.append(
                f"<table><thead><tr>{thead}</tr></thead><tbody>{body}</tbody></table>"
            )
            continue

        if line.lstrip().startswith(">"):
            buf = []
            while i < n and lines[i].lstrip().startswith(">"):
                buf.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            out.append(f"<blockquote>{md_to_html(chr(10).join(buf), mark_code)}</blockquote>")
            continue

        m = re.match(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$", line)
        if m:
            ordered = bool(re.match(r"\d", m.group(2)))
            tag = "ol" if ordered else "ul"
            items: list[str] = []
            while i < n:
                mm = re.match(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$", lines[i])
                if mm:
                    items.append(mm.group(3))
                    i += 1
                elif items and lines[i].strip() and lines[i].startswith((" ", "\t")):
                    items[-1] += " " + lines[i].strip()
                    i += 1
                else:
                    break
            lis = "".join(f"<li>{_inline(it)}</li>" for it in items)
            out.append(f"<{tag}>{lis}</{tag}>")
            continue

        buf = [line]
        i += 1
        while i < n and lines[i].strip() and not _BLOCK_START.match(lines[i]):
            buf.append(lines[i])
            i += 1
        out.append("<p>" + "<br>".join(_inline(s.rstrip()) for s in buf) + "</p>")

    return "\n".join(out)


# --------------------------------------------------------------------------- #
#  message rendering
# --------------------------------------------------------------------------- #

def render_image(source: dict) -> str:
    if source.get("type") == "base64" and source.get("data"):
        mt = source.get("media_type", "image/png")
        return f'<img alt="embedded image" src="data:{mt};base64,{source["data"]}">'
    return "<p><em>[image]</em></p>"


def fold(header_html: str, body_html: str, kind: str, extra_class: str = "") -> str:
    """A collapsible panel. Uses an explicit .open class toggled by JS rather
    than <details>, so it can't be defeated by browser/CSS quirks. `kind` is
    tagged as data-kind so "reading mode" can hide tool/thinking panels."""
    cls = ("fold " + extra_class).strip()
    return (
        f'<div class="{cls}" data-kind="{kind}">'
        f'<div class="fold-h" role="button" tabindex="0">{header_html}</div>'
        f'<div class="fold-c">{body_html}</div></div>'
    )


def render_tool_use(blk: dict) -> str:
    name = html.escape(str(blk.get("name", "tool")))
    try:
        pretty = json.dumps(blk.get("input", {}), indent=2, ensure_ascii=False)
    except (TypeError, ValueError):
        pretty = str(blk.get("input", ""))
    body = html.escape(pretty, quote=False)
    return fold(
        f"&#128295; tool call &middot; <b>{name}</b>",
        f'<pre><code class="language-json">{body}</code></pre>',
        "tool_use",
    )


def render_tool_result(blk: dict, max_result: int) -> str:
    content = blk.get("content", "")
    images: list[str] = []
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        chunks = []
        for x in content:
            if isinstance(x, dict):
                if x.get("type") == "text":
                    chunks.append(x.get("text", ""))
                elif x.get("type") == "image":
                    # e.g. Read on a screenshot — this is the actual image
                    # data, not a stand-in; render it, don't stub it to text.
                    images.append(render_image(x.get("source", {})))
                else:
                    chunks.append(json.dumps(x, ensure_ascii=False))
            else:
                chunks.append(str(x))
        text = "\n".join(chunks)
    else:
        text = str(content)

    full_len = len(text)
    if max_result and full_len > max_result:
        text = text[:max_result] + f"\n\n… [truncated {full_len - max_result} chars]"

    is_err = bool(blk.get("is_error"))
    label = "&#9888; tool result (error)" if is_err else "&#128196; tool result"
    size_note = f"{full_len} chars" if text.strip() else (
        f"{len(images)} image{'s' if len(images) != 1 else ''}" if images else "0 chars")
    body = "".join(images)
    if text.strip():
        body += f"<pre>{html.escape(text, quote=False)}</pre>"
    extra = "err" if is_err else ""
    if images:
        # exempted from "Collapse all" / Reading mode by default — see .has-img CSS
        extra = (extra + " has-img").strip()
    return fold(
        f'{label} <span class="muted">({size_note})</span>',
        body,
        "tool_result",
        extra,
    )


def render_blocks(content, max_result: int, mark_code: bool = False) -> list[tuple[str, str]]:
    parts: list[tuple[str, str]] = []
    if isinstance(content, str):
        return [("text", md_to_html(content, mark_code))]
    for blk in content or []:
        if not isinstance(blk, dict):
            parts.append(("text", md_to_html(str(blk), mark_code)))
            continue
        t = blk.get("type")
        if t == "text":
            parts.append(("text", md_to_html(blk.get("text", ""), mark_code)))
        elif t == "thinking":
            parts.append(
                ("thinking", fold("&#128173; thinking",
                                  md_to_html(blk.get("thinking", "")), "thinking", "think"))
            )
        elif t == "redacted_thinking":
            parts.append(("thinking", '<p class="muted"><em>[redacted thinking]</em></p>'))
        elif t == "tool_use":
            parts.append(("tool_use", render_tool_use(blk)))
        elif t == "tool_result":
            parts.append(("tool_result", render_tool_result(blk, max_result)))
        elif t == "image":
            parts.append(("image", render_image(blk.get("source", {}))))
        else:
            parts.append(
                ("text", f"<pre>{html.escape(json.dumps(blk, indent=2, ensure_ascii=False))}</pre>")
            )
    return parts


def first_text_snippet(content) -> str:
    if isinstance(content, str):
        s = content
    else:
        s = ""
        for b in content or []:
            if isinstance(b, dict) and b.get("type") == "text":
                s = b.get("text", "")
                break
    s = re.sub(r"<system-reminder>.*?</system-reminder>", "", s, flags=re.S)
    s = re.sub(r"\s+", " ", s).strip()
    return (s[:90] + "…") if len(s) > 90 else s or "(no text)"


# Slash commands whose output tends to carry things that don't belong in a
# shared/committed transcript (session IDs, token/cost breakdowns, internal
# plumbing) rather than actual project discussion. Redacted by default —
# --keep-diagnostic-commands on the CLI turns this off.
SENSITIVE_COMMANDS = {
    "cost", "usage", "context", "status", "doctor",
    "explain-usage", "anthropic-skills:explain-usage",
}
_COMMAND_NAME_RE = re.compile(r"<command-name>/?([^<]+)</command-name>")

# Email addresses show up unpredictably — a `git config` output, a memory file,
# an aside in conversation — not from one fixable spot like the session ID or a
# known command. Scrubbed globally from the finished page by default;
# --keep-emails turns it off for a private copy.
EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")


def _raw_text(content) -> str:
    if isinstance(content, str):
        return content
    parts = []
    for b in content or []:
        if isinstance(b, dict) and b.get("type") == "text":
            parts.append(b.get("text", ""))
    return "\n".join(parts)


def sensitive_command_name(content) -> str | None:
    """The invoked command name if this user turn matches SENSITIVE_COMMANDS
    (checked both as the full name and as the part after a skill namespace
    ':'), else None."""
    m = _COMMAND_NAME_RE.search(_raw_text(content))
    if not m:
        return None
    name = m.group(1).strip().lower()
    if name in SENSITIVE_COMMANDS or name.rsplit(":", 1)[-1] in SENSITIVE_COMMANDS:
        return name
    return None


# --------------------------------------------------------------------------- #
#  page assembly
# --------------------------------------------------------------------------- #

ROLE_LABEL = {
    "user": "You",
    "assistant": "Claude",
    "tool": "Tool",
    "summary": "Context summary",
    "system": "System",
    "redacted": "Redacted",
}


def build_turns(events, *, drop_meta: bool, max_result: int, redact_commands: bool = True):
    turns = []
    redacting = False  # inside a skipped /cost-style command-and-response window
    for ev in events:
        if drop_meta and ev.get("isMeta"):
            continue
        et = ev.get("type")
        ts = fmt_ts(ev.get("timestamp"))
        side = bool(ev.get("isSidechain"))

        if et == "summary":
            turns.append(
                dict(role="summary", ts=ts, side=False,
                     html=md_to_html(ev.get("summary", "")), snippet=None)
            )
            continue

        msg = ev.get("message")
        if not isinstance(msg, dict):
            continue
        role = msg.get("role", et or "system")
        content = msg.get("content")

        if role == "user":
            cmd = sensitive_command_name(content) if redact_commands else None
            if cmd:
                redacting = True
                turns.append(dict(
                    role="redacted", ts=ts, side=False, no_prose=False,
                    html=f"<p><em>— /{html.escape(cmd)} output omitted from this export —</em></p>",
                    snippet=None,
                ))
                continue
            redacting = False  # any other user turn ends a redaction window
        elif redacting:
            continue  # assistant/tool turn inside a redacted command's response

        blocks = render_blocks(content, max_result, mark_code=(role == "assistant"))
        if not blocks:
            continue

        kinds = {k for k, _ in blocks}
        disp = "tool" if (role == "user" and kinds and kinds <= {"tool_result", "image"}) else role
        # an assistant turn that is only tool calls / thinking (no prose) -> can be
        # hidden entirely in "reading mode"
        no_prose = disp == "assistant" and not (kinds & {"text", "image"})
        turn_html = "\n".join(h for _, h in blocks)
        # a tool result that embedded a real image (e.g. Read on a screenshot) —
        # exempted from "Collapse all" / Reading mode by default, see .has-img CSS
        has_image = "<img " in turn_html

        turns.append(
            dict(
                role=disp,
                ts=ts,
                side=side,
                no_prose=no_prose,
                has_image=has_image,
                html=turn_html,
                snippet=first_text_snippet(content) if disp == "user" else None,
            )
        )
    return turns


PAGE_CSS = """
:root{
  --bg:#0f1115; --panel:#171a21; --panel2:#1d212b; --text:#dfe3ea; --muted:#8b93a3;
  --border:#2a2f3a; --user:#5fb3d4; --assistant:#7ec27e; --tool:#a2a9b8;
  --summary:#e0b25a; --accent:#7aa2f7; --code-bg:#11141a;
}
@media (prefers-color-scheme: light){
  :root:not([data-theme]){
    --bg:#f6f7f9; --panel:#ffffff; --panel2:#f0f2f5; --text:#1c2230; --muted:#5b6472;
    --border:#dfe3ea; --user:#1f7aa8; --assistant:#2f8a3f; --tool:#5c6472;
    --summary:#a5761a; --accent:#3355cc; --code-bg:#f2f4f7;
  }
}
:root[data-theme=light]{
  --bg:#f6f7f9; --panel:#ffffff; --panel2:#f0f2f5; --text:#1c2230; --muted:#5b6472;
  --border:#dfe3ea; --user:#1f7aa8; --assistant:#2f8a3f; --tool:#5c6472;
  --summary:#a5761a; --accent:#3355cc; --code-bg:#f2f4f7;
}
:root[data-theme=dark]{
  --bg:#0f1115; --panel:#171a21; --panel2:#1d212b; --text:#dfe3ea; --muted:#8b93a3;
  --border:#2a2f3a; --user:#5fb3d4; --assistant:#7ec27e; --tool:#a2a9b8;
  --summary:#e0b25a; --accent:#7aa2f7; --code-bg:#11141a;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Ubuntu,sans-serif}
a{color:var(--accent)}
.wrap{display:grid;grid-template-columns:260px minmax(0,1fr);gap:0;max-width:1180px;margin:0 auto}
nav{position:sticky;top:0;align-self:start;height:100vh;overflow:auto;
  padding:18px 14px;border-right:1px solid var(--border);background:var(--panel)}
nav h2{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:0 0 10px}
nav ol{margin:0;padding:0;list-style:none;counter-reset:q}
nav li{counter-increment:q;margin:0 0 4px}
nav a{display:block;padding:6px 8px;border-radius:6px;text-decoration:none;color:var(--text);
  font-size:13px;border:1px solid transparent}
nav a:hover{background:var(--panel2);border-color:var(--border)}
nav a::before{content:counter(q) ". ";color:var(--muted)}
main{padding:26px 30px 120px;min-width:0}
header.doc{margin-bottom:24px;padding-bottom:16px;border-bottom:1px solid var(--border)}
header.doc h1{font-size:19px;margin:0 0 6px}
header.doc .meta{color:var(--muted);font-size:12.5px}
.toolbar{margin:14px 0 0;display:flex;gap:8px;flex-wrap:wrap}
.toolbar button{background:var(--panel2);color:var(--text);border:1px solid var(--border);
  border-radius:6px;padding:5px 10px;font-size:12.5px;cursor:pointer}
.toolbar button:hover{border-color:var(--accent)}
.toolbar button.on{background:var(--accent);border-color:var(--accent);color:#fff}
.imgs-toggle{display:flex;align-items:center;gap:5px;font-size:12.5px;color:var(--muted);
  border:1px solid var(--border);border-radius:6px;padding:5px 10px;cursor:pointer}
.turn{margin:18px 0;padding:14px 16px;border:1px solid var(--border);border-radius:10px;background:var(--panel)}
.turn.user{border-left:3px solid var(--user)}
.turn.assistant{border-left:3px solid var(--assistant)}
.turn.tool{border-left:3px solid var(--tool);background:var(--panel2)}
.turn.summary{border-left:3px solid var(--summary)}
.turn.redacted{border-left:3px dashed var(--muted);opacity:.75}
.turn .who{font-weight:700;font-size:12px;letter-spacing:.05em;text-transform:uppercase}
.turn.user .who{color:var(--user)} .turn.assistant .who{color:var(--assistant)}
.turn.tool .who{color:var(--tool)} .turn.summary .who{color:var(--summary)}
.turn.redacted .who{color:var(--muted)}
.turn .when{color:var(--muted);font-size:11.5px;margin-left:8px;font-weight:400;text-transform:none;letter-spacing:0}
.turn .sidechain{color:var(--accent);font-size:11px;margin-left:8px}
.body{margin-top:8px}
.body>*:first-child{margin-top:0}
.body>*:last-child{margin-bottom:0}
.body h1,.body h2,.body h3,.body h4{line-height:1.3;margin:1.1em 0 .5em}
.body h1{font-size:1.3em} .body h2{font-size:1.18em} .body h3{font-size:1.05em}
.body p{margin:.55em 0}
.body ul,.body ol{margin:.5em 0;padding-left:1.5em}
.body blockquote{margin:.6em 0;padding:.1em 0 .1em 1em;border-left:3px solid var(--border);color:var(--muted)}
.body code{background:var(--code-bg);border:1px solid var(--border);border-radius:4px;
  padding:.08em .35em;font-size:.9em;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.body pre{background:var(--code-bg);border:1px solid var(--border);border-radius:8px;
  padding:12px 14px;overflow:auto;margin:.7em 0}
.body pre code{background:none;border:0;padding:0;font-size:12.5px;line-height:1.5}
.body table{border-collapse:collapse;margin:.7em 0;display:block;overflow:auto}
.body th,.body td{border:1px solid var(--border);padding:5px 10px;text-align:left}
.body th{background:var(--panel2)}
.body img{max-width:100%;border:1px solid var(--border);border-radius:6px}
.fold{margin:.7em 0;border:1px solid var(--border);border-radius:8px;
  background:var(--code-bg);overflow:hidden}
.fold-h{cursor:pointer;padding:8px 12px;font-size:12.5px;color:var(--muted);
  user-select:none;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.fold-h:hover{color:var(--text)}
.fold-h:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
.fold-h::before{content:"\\25B8  ";color:var(--muted)}
.fold.open>.fold-h::before{content:"\\25BE  "}
.fold-c{display:none;border-top:1px solid var(--border)}
.fold.open>.fold-c{display:block}
.fold-c>pre{margin:0;border:0;border-radius:0}
.fold.think{background:transparent}
.fold.think>.fold-h{color:var(--accent)}
.fold.think>.fold-c{padding:2px 12px 10px;border-top-color:var(--border)}
.fold.err{border-color:#a44}
.muted{color:var(--muted)}
#top{position:fixed;right:20px;bottom:20px;background:var(--panel2);border:1px solid var(--border);
  color:var(--text);border-radius:20px;padding:8px 14px;text-decoration:none;font-size:12.5px}
@media (max-width:860px){
  .wrap{grid-template-columns:1fr}
  nav{position:static;height:auto;border-right:0;border-bottom:1px solid var(--border)}
  main{padding:18px 16px 100px}
}

/* Reading mode: drop every mechanical block (also affects the PDF) — except
   a tool result that embedded a real image (e.g. Read on a screenshot); that
   stays visible unless the "Always show images" checkbox is switched off. */
body.reading .fold[data-kind="tool_use"],
body.reading .fold[data-kind="thinking"],
body.reading .fold[data-kind="tool_result"]:not(.has-img),
body.reading .turn.tool:not(.has-img),
body.reading .turn.assistant.no-prose{display:none}

/* Collapse all / Reading mode: a fold with an image stays open by default —
   BUT a direct click on that one fold's header still hides that one image
   (adds .img-hidden; independent of the generic .open class, so "Collapse
   all"/Reading mode can't clobber a deliberate per-image click, and vice
   versa). Blank/unwanted screenshots can be closed one at a time this way. */
.fold.has-img>.fold-c{display:block}
.fold.has-img.img-hidden>.fold-c{display:none}
.fold.has-img>.fold-h::before{content:"\\25BE  "}
.fold.has-img.img-hidden>.fold-h::before{content:"\\25B8  "}

/* "Always show images" switched off: images obey plain collapse/reading rules
   (click then toggles the normal .open class instead — see toggleFold()). */
body.imgs-strict .fold.has-img:not(.open)>.fold-c{display:none}
body.imgs-strict .fold.has-img:not(.open)>.fold-h::before{content:"\\25B8  "}
body.imgs-strict .fold.has-img.open>.fold-h::before{content:"\\25BE  "}
body.imgs-strict.reading .fold[data-kind="tool_result"],
body.imgs-strict.reading .turn.tool{display:none}

/* Claude's own example/solution code fences (written directly in its prose,
   not a tool diff/output) — outside Reading mode these render exactly like
   plain Markdown code, no extra chrome at all (the fold header stays hidden). */
.fold.doc-code>.fold-h{display:none}
.fold.doc-code>.fold-c{display:block;border-top:0;padding:0}
.fold.doc-code>.fold-c>pre{margin:.7em 0}

/* Reading mode, "Show example code" unchecked (default): hidden — code
   examples are common enough that showing them all by default would defeat
   the point of Reading mode, unlike the rare has-img case. Individually
   revealable per block via the ordinary .open mechanism (same one used by
   every other fold/"Expand all tools"), so a manual reveal survives toggling
   the checkbox later — exactly like a single has-img fold's state survives
   toggling "Always show images". */
body.reading .fold.doc-code>.fold-h{display:block}
body.reading .fold.doc-code>.fold-c{display:none}
body.reading .fold.doc-code.open>.fold-c{display:block}
body.reading .fold.doc-code.open>.fold-h::before{content:"\\25BE  "}

/* "Show example code" checked: default flips to shown; a click on one then
   hides just that one via .code-hidden (independent of .open, mirroring
   .img-hidden vs imgs-strict). */
body.reading.code-show .fold.doc-code>.fold-c{display:block}
body.reading.code-show .fold.doc-code>.fold-h::before{content:"\\25BE  "}
body.reading.code-show .fold.doc-code.code-hidden>.fold-c{display:none}
body.reading.code-show .fold.doc-code.code-hidden>.fold-h::before{content:"\\25B8  "}

/* ---- print / PDF ---- */
@media print{
  :root{
    --bg:#fff;--panel:#fff;--panel2:#f1f1f1;--text:#111;--muted:#555;
    --border:#c9c9c9;--user:#1f6f97;--assistant:#2c7a3a;--tool:#666;
    --summary:#8a6100;--accent:#2033aa;--code-bg:#f6f6f6;
  }
  body{background:#fff}
  .toolbar,#top{display:none !important}
  .wrap{display:block;max-width:none}
  nav{position:static;height:auto;overflow:visible;border:0;padding:0;
    page-break-after:always;break-after:page}
  nav h2{font-size:15pt;margin:0 0 8pt}
  nav ol{padding:0;margin:0}
  nav li{margin:0 0 3pt;break-inside:avoid;page-break-inside:avoid}
  nav a{display:block;font-size:10.5pt;line-height:1.35;padding:0 0 0 1.7em;border:0;
    border-radius:0;text-indent:-1.7em;
    white-space:normal !important;overflow:visible !important;text-overflow:clip !important;
    overflow-wrap:anywhere;word-break:break-word}
  nav a::before{content:counter(q) ". "}
  nav a:hover{background:none}
  .body h1,.body h2,.body h3,.body h4,.turn .who{overflow-wrap:anywhere;word-break:break-word}
  main{padding:0}
  header.doc{border-bottom:1px solid var(--border)}
  .turn{margin:10pt 0;border:0;border-left:2.5pt solid var(--border);
    border-radius:0;padding:4pt 0 4pt 10pt;background:none;break-inside:auto}
  .turn .when,.turn .sidechain{color:var(--muted)}
  .body pre{white-space:pre-wrap;word-break:break-word;overflow:visible}
  .fold{break-inside:avoid}
  .fold-h{white-space:normal}
  /* Cap oversized screenshots to well within one A4 page (~29.7cm, minus
     margins) so a single huge image can't spill onto a mostly-blank next
     page — the actual cause of "empty page after this image" in exports. */
  .body img{max-width:15cm;max-height:20cm;width:auto;height:auto;
    display:block;margin:6pt auto;page-break-inside:avoid;break-inside:avoid}
  a{color:var(--text);text-decoration:none}
  .body a{color:var(--accent)}
}
"""

PAGE_JS = """
document.querySelectorAll('pre code').forEach(function(el){
  try{ if(window.hljs) hljs.highlightElement(el); }catch(e){}
});
function toggleFold(el){
  if(!el) return;
  // has-img folds default open regardless of .open (see CSS) — a click hides
  // just that one image via .img-hidden instead, unless "Always show images"
  // is switched off, in which case they behave like any other fold again.
  if(el.classList.contains('has-img') && !document.body.classList.contains('imgs-strict')){
    el.classList.toggle('img-hidden');
  } else if(el.classList.contains('doc-code') && document.body.classList.contains('code-show')){
    el.classList.toggle('code-hidden');
  } else {
    // plain folds, has-img under imgs-strict, AND doc-code with the checkbox
    // unchecked (its default-hidden state reuses the ordinary open mechanism)
    el.classList.toggle('open');
  }
}
document.addEventListener('click', function(e){
  var h = e.target.closest && e.target.closest('.fold-h');
  if(h) toggleFold(h.parentElement);
});
document.addEventListener('keydown', function(e){
  if((e.key === 'Enter' || e.key === ' ') && e.target.classList &&
     e.target.classList.contains('fold-h')){
    e.preventDefault(); toggleFold(e.target.parentElement);
  }
});
function setAllFolds(open){
  document.querySelectorAll('.fold').forEach(function(d){ d.classList.toggle('open', open); });
}
var be = document.getElementById('exp'); if(be) be.onclick = function(){ setAllFolds(true); };
var bc = document.getElementById('col'); if(bc) bc.onclick = function(){ setAllFolds(false); };

var br = document.getElementById('reading');
if(br) br.onclick = function(){
  var on = document.body.classList.toggle('reading');
  br.classList.toggle('on', on);
  br.textContent = on ? 'Reading mode: ON' : 'Reading mode';
};

var bi = document.getElementById('imgs');
if(bi) bi.onchange = function(){
  document.body.classList.toggle('imgs-strict', !bi.checked);
};

var bcode = document.getElementById('code');
if(bcode) bcode.onchange = function(){
  document.body.classList.toggle('code-show', bcode.checked);
};

var bt = document.getElementById('theme');
if(bt) bt.onclick = function(){
  var r = document.documentElement;
  var dark = r.dataset.theme ? (r.dataset.theme === 'dark')
           : window.matchMedia('(prefers-color-scheme: dark)').matches;
  r.dataset.theme = dark ? 'light' : 'dark';
};

var bp = document.getElementById('pdf');
if(bp) bp.onclick = function(){ window.print(); };
"""


def render_page(turns, *, title: str, source: str, session_id: str,
                force_light: bool, show_ids: bool = False) -> str:
    nav_items = []
    body_parts = []
    q = 0
    for idx, t in enumerate(turns):
        anchor = f"t{idx}"
        role = t["role"]
        label = ROLE_LABEL.get(role, role.title())
        when = f'<span class="when">{html.escape(t["ts"])}</span>' if t["ts"] else ""
        side = '<span class="sidechain">subagent</span>' if t["side"] else ""
        klass = f"turn {html.escape(role)}" + (" no-prose" if t.get("no_prose") else "") \
            + (" has-img" if t.get("has_image") else "")
        body_parts.append(
            f'<section class="{klass}" id="{anchor}">'
            f'<div class="who">{label}{when}{side}</div>'
            f'<div class="body">{t["html"]}</div></section>'
        )
        if role == "user" and t.get("snippet"):
            q += 1
            nav_items.append(
                f'<li><a href="#{anchor}">{html.escape(t["snippet"])}</a></li>'
            )

    nav_html = (
        '<nav><h2>Your messages</h2><ol>' + "".join(nav_items) + "</ol></nav>"
        if nav_items
        else "<nav><h2>Transcript</h2></nav>"
    )
    theme_attr = ' data-theme="light"' if force_light else ""
    # The source filename and session id are internal identifiers (a stray
    # UUID in an otherwise clean showcase doc) — off by default, --show-ids
    # brings them back for personal debugging copies that never leave disk.
    ids = (
        f"{html.escape(source)} &middot; session {html.escape(session_id or 'n/a')} &middot; "
        if show_ids else ""
    )
    meta = (
        f"{ids}{len(turns)} entries &middot; generated "
        f"{dt.datetime.now().strftime('%Y-%m-%d %H:%M')}"
    )

    return f"""<!doctype html>
<html lang="en"{theme_attr}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<link rel="stylesheet"
  href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
<style>{PAGE_CSS}</style>
</head>
<body>
<div class="wrap">
{nav_html}
<main>
<header class="doc">
  <h1>{html.escape(title)}</h1>
  <div class="meta">{meta}</div>
  <div class="toolbar">
    <button id="exp">Expand all tools</button>
    <button id="col">Collapse all tools</button>
    <button id="reading" title="Hide every tool call, tool result and thinking block">Reading mode</button>
    <label class="imgs-toggle" title="Keep tool-result images visible even when their panel is collapsed or Reading mode is on. Click one image's own header to hide just that one (e.g. a blank/unwanted screenshot).">
      <input type="checkbox" id="imgs" checked> Always show images
    </label>
    <label class="imgs-toggle" title="Reading mode normally hides every fenced code block Claude writes directly in its own prose (a solution snippet, not a diff or tool output). Check this to reveal them all, or click one such block's own header to reveal just that one.">
      <input type="checkbox" id="code"> Show example code
    </label>
    <button id="theme">Toggle light / dark</button>
    <button id="pdf" title="Opens the browser print dialog – choose &quot;Save as PDF&quot;. Whatever is hidden or collapsed now is left out of the PDF.">Export to PDF</button>
  </div>
</header>
{''.join(body_parts)}
</main>
</div>
<a id="top" href="#">&#8679; top</a>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>{PAGE_JS}</script>
</body>
</html>
"""


# --------------------------------------------------------------------------- #
#  cli
# --------------------------------------------------------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("transcript", nargs="?", type=Path,
                    help="path to a Claude Code *.jsonl transcript")
    ap.add_argument("-o", "--output", type=Path)
    ap.add_argument("--latest", action="store_true",
                    help="use the newest transcript under ~/.claude/projects/")
    ap.add_argument("--title")
    ap.add_argument("--open", action="store_true")
    ap.add_argument("--max-result", type=int, default=20000)
    ap.add_argument("--no-meta", action="store_true")
    ap.add_argument("--light", action="store_true")
    ap.add_argument("--show-ids", action="store_true",
                    help="include the source filename and session UUID in the page header "
                         "(off by default — keeps that identifier out of a shared/committed export)")
    ap.add_argument("--keep-diagnostic-commands", action="store_true",
                    help="don't redact /cost, /usage, /context, /explain-usage etc. turns "
                         "(see SENSITIVE_COMMANDS) — off by default")
    ap.add_argument("--keep-emails", action="store_true",
                    help="don't mask email addresses found anywhere in the page — off by "
                         "default (they turn up unpredictably: a git config dump, a memory "
                         "file, an aside in conversation, not just one fixable spot)")
    args = ap.parse_args()

    src: Path | None = args.transcript
    if args.latest or src is None:
        src = find_latest_transcript() if (args.latest or src is None) else src
    if src is None or not src.is_file():
        print("error: no transcript file found. Pass a path or use --latest.",
              file=sys.stderr)
        return 2

    events = load_events(src)
    if not events:
        print("error: transcript is empty or unreadable.", file=sys.stderr)
        return 1

    session_id = ""
    for ev in events:
        if ev.get("sessionId"):
            session_id = str(ev["sessionId"])
            break

    turns = build_turns(events, drop_meta=args.no_meta, max_result=args.max_result,
                        redact_commands=not args.keep_diagnostic_commands)
    title = args.title or "Claude Code transcript"
    page = render_page(turns, title=title, source=src.name, session_id=session_id,
                       force_light=args.light, show_ids=args.show_ids)

    # Hiding session_id from the header isn't enough on its own — this session's
    # own scratchpad dir (Claude's working-file convention) is named after the
    # session UUID, so any Bash command that touched it embeds the raw ID in a
    # tool call/result the header-only fix wouldn't catch. Scrub every literal
    # occurrence instead.
    if session_id and not args.show_ids and session_id in page:
        page = page.replace(session_id, "session")

    if not args.keep_emails:
        page = EMAIL_RE.sub("[email hidden]", page)

    out = args.output or src.with_suffix(".html")
    out.write_text(page, encoding="utf-8")
    print(f"wrote {out}  ({out.stat().st_size / 1024:.0f} KB, {len(turns)} entries)")

    if args.open:
        webbrowser.open(out.resolve().as_uri())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
