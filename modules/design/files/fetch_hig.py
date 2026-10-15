#!/usr/bin/env python3
"""Fetch Apple's Human Interface Guidelines as Markdown, one file per page.

Source: Apple's own JSON data behind developer.apple.com/design/human-interface-guidelines.
Re-run any time to refresh: python3 fetch_hig.py
Output: reference/<group>/<slug>.md plus reference/INDEX.md. Content is Apple's (copyright
notice kept in every file); this is a local reading copy for design work, not for redistribution.
"""
import argparse
import json
import pathlib
import time
import urllib.request

BASE = "https://developer.apple.com/tutorials/data/design/human-interface-guidelines"
WEB = "https://developer.apple.com/design/human-interface-guidelines"
OUT = pathlib.Path(__file__).resolve().parent / "reference"


def slug_of(ident):
    return ident.rstrip("/").split("/")[-1].lower()


def get(slug):
    url = BASE + ("" if slug is None else "/" + slug) + ".json"
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.load(r)
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2)


def inline(nodes, refs):
    out = []
    for n in nodes or []:
        t = n.get("type")
        if t == "text":
            out.append(n["text"])
        elif t == "strong":
            out.append("**" + inline(n.get("inlineContent"), refs) + "**")
        elif t == "emphasis":
            out.append("*" + inline(n.get("inlineContent"), refs) + "*")
        elif t == "codeVoice":
            out.append("`" + n.get("code", "") + "`")
        elif t == "reference":
            ident = n.get("identifier", "")
            title = n.get("overridingTitle") or refs.get(ident, {}).get("title") or slug_of(ident)
            if "com.apple.HIG" in ident:
                page, _, anchor = slug_of(ident).partition("#")
                out.append(f"[{title}]({page}.md{'#' + anchor if anchor else ''})")
            else:
                url = refs.get(ident, {}).get("url", "")
                out.append(f"[{title}]({url})" if url.startswith("http") else title)
        elif t == "image":
            alt = refs.get(n.get("identifier", ""), {}).get("alt")
            if alt:
                out.append(f"[Image: {alt}]")
        elif "inlineContent" in n:
            out.append(inline(n["inlineContent"], refs))
    return "".join(out)


def blocks(nodes, refs, indent=""):
    lines = []
    for n in nodes or []:
        t = n.get("type")
        if t == "heading":
            lines.append("#" * min(n.get("level", 2) + 1, 6) + " " + n.get("text", ""))
        elif t == "paragraph":
            txt = inline(n.get("inlineContent"), refs).strip()
            if txt:
                lines.append(indent + txt)
        elif t in ("unorderedList", "orderedList"):
            for i, item in enumerate(n.get("items", []), 1):
                mark = f"{i}." if t == "orderedList" else "-"
                body = blocks(item.get("content"), refs, indent + "  ").strip()
                lines.append(f"{indent}{mark} {body.lstrip()}")
            lines.append("")
            continue
        elif t == "aside":
            body = blocks(n.get("content"), refs).strip().replace("\n", "\n> ")
            lines.append(f"> **{n.get('name') or n.get('style', 'Note').title()}:** {body}")
        elif t == "table":
            rows = n.get("rows", [])
            for r_i, row in enumerate(rows):
                cells = [blocks(c, refs).strip().replace("\n", " ") for c in row]
                lines.append("| " + " | ".join(cells) + " |")
                if r_i == 0:
                    lines.append("|" + "---|" * len(cells))
        elif t == "row":
            for col in n.get("columns", []):
                lines.append(blocks(col.get("content"), refs, indent).strip())
        elif "content" in n:
            lines.append(blocks(n["content"], refs, indent))
        lines.append("")
    return "\n".join(lines)


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=OUT)
    OUT = parser.parse_args().output
    OUT.mkdir(parents=True, exist_ok=True)
    root = get(None)
    index = ["# Apple HIG index", "", f"Fetched {time.strftime('%Y-%m-%d')} from {WEB}", ""]
    seen = set()

    def visit(ident, depth, group):
        slug = slug_of(ident)
        if slug in seen:
            return
        seen.add(slug)
        data = get(slug)
        title = data.get("metadata", {}).get("title", slug)
        refs = data.get("references", {})
        abstract = inline(data.get("abstract"), refs)
        children = [i for s in data.get("topicSections", []) for i in s.get("identifiers", [])
                    if "com.apple.HIG" in i]
        if data.get("primaryContentSections"):
            body = "\n".join(blocks(s.get("content"), refs) for s in data["primaryContentSections"])
            notice = data.get("legalNotices", {}).get("copyright", "Copyright Apple Inc.")
            updated = data.get("metadata", {}).get("customMetadata", {}).get("alert-date", "")
            md = (f"# {title}\n\n> {abstract}\n\nSource: {WEB}/{slug}"
                  + (f" (updated {updated})" if updated else "")
                  + f"\n\n{body.strip()}\n\n---\n{notice.replace('&copy;', '©')}\n")
            dest = OUT / group / f"{slug}.md"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(md)
            index.append(f"{'  ' * depth}- [{title}]({group}/{slug}.md): {abstract}")
        else:
            index.append(f"{'  ' * depth}- **{title}**: {abstract}")
        for child in children:
            visit(child, depth + 1, group if depth else slug)
        time.sleep(0.2)

    for section in root.get("topicSections", []):
        for ident in section.get("identifiers", []):
            visit(ident, 0, slug_of(ident))
    (OUT / "INDEX.md").write_text("\n".join(index) + "\n")
    print(f"{len(seen)} pages -> {OUT}")


if __name__ == "__main__":
    main()
