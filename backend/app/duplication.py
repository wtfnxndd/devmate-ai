"""Copy-paste (clone) detection across the whole project.

Lines are normalised (whitespace collapsed, blank lines and comment-only lines dropped), then every
window of MIN_LINES consecutive lines is hashed. Windows that occur more than once are merged into the
longest matching blocks, which is the classic approach used by tools such as PMD CPD and jscpd.
"""
import hashlib
import re
from collections import defaultdict

from .ingest import iter_source_files

MIN_LINES = 6
COMMENT = re.compile(r"^(#|//|/\*|\*|\*/|--|<!--)")


def _normalise(text: str):
    """Returns [(original_line_number, normalised_text)] for meaningful lines."""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        s = re.sub(r"\s+", " ", line.strip())
        if len(s) < 3 or COMMENT.match(s) or s in ("{", "}", ")", "]", "});", "end", "else:", "pass"):
            continue
        out.append((i, s))
    return out


def find_duplicates(root, min_lines: int = MIN_LINES) -> dict:
    files = {rel: (_normalise(text), text.splitlines()) for rel, _lang, text in iter_source_files(root)}
    windows = defaultdict(list)  # hash -> [(file, index into normalised lines)]
    total = 0
    for rel, (norm, _) in files.items():
        total += len(norm)
        for i in range(len(norm) - min_lines + 1):
            h = hashlib.md5("\n".join(s for _, s in norm[i : i + min_lines]).encode(), usedforsecurity=False).hexdigest()
            windows[h].append((rel, i))

    # Extend every repeated window into the longest block shared by the same set of locations.
    seen, blocks = set(), []
    for locs in windows.values():
        if len(locs) < 2:
            continue
        locs = sorted(set(locs))
        if all(loc in seen for loc in locs):
            continue
        length = min_lines
        while True:
            nxt = [(f, i + length) for f, i in locs]
            if not all(i < len(files[f][0]) for f, i in nxt):
                break
            if len({files[f][0][i][1] for f, i in nxt}) != 1:
                break
            length += 1
        occurrences = []
        for f, i in locs:
            for k in range(length - min_lines + 1):
                seen.add((f, i + k))
            norm = files[f][0]
            occurrences.append({"file": f, "start": norm[i][0], "end": norm[i + length - 1][0]})
        # Overlapping windows inside one file (e.g. repeated lines) are not real clones.
        if len({(o["file"], o["start"]) for o in occurrences}) < 2:
            continue
        first = occurrences[0]
        snippet = "\n".join(files[first["file"]][1][first["start"] - 1 : first["end"]])
        blocks.append({"lines": length, "occurrences": occurrences, "snippet": snippet[:3000]})

    blocks.sort(key=lambda b: -(b["lines"] * (len(b["occurrences"]) - 1)))
    duplicated = sum(b["lines"] * (len(b["occurrences"]) - 1) for b in blocks)
    return {
        "blocks": blocks[:100],
        "duplicated_lines": duplicated,
        "total_lines": total,
        "percentage": round(100 * duplicated / total, 1) if total else 0.0,
    }


def as_findings(dup: dict) -> list:
    out = []
    for b in dup["blocks"][:40]:
        others = ", ".join(f"{o['file']}:{o['start']}" for o in b["occurrences"][1:4])
        for o in b["occurrences"][:1]:
            out.append({
                "tool": "devmate-clones", "rule": "duplicate-code", "category": "smell",
                "severity": "medium" if b["lines"] >= 15 else "low",
                "file": o["file"], "line": o["start"],
                "message": f"{b['lines']} lines duplicated in {len(b['occurrences'])} places (also {others})",
            })
    return out
