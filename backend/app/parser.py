"""Tree-sitter AST parsing: extracts classes, functions, imports and the dependency graph."""
import re
from collections import Counter
from pathlib import Path, PurePosixPath

from tree_sitter_language_pack import get_parser

from .ingest import iter_source_files

FUNCTION_TYPES = {
    "function_definition", "function_declaration", "method_definition", "method_declaration",
    "function_item", "constructor_declaration", "function_signature", "method_signature",
    "generator_function_declaration",
}
CLASS_TYPES = {
    "class_definition", "class_declaration", "interface_declaration", "struct_item",
    "enum_declaration", "trait_item", "impl_item", "struct_specifier", "class_specifier",
    "type_declaration", "mixin_declaration",
}
IMPORT_TYPES = {
    "import_statement", "import_from_statement", "import_declaration", "use_declaration",
    "preproc_include", "import_or_export", "import_specification", "namespace_use_declaration",
}

_parsers = {}


def _parser(lang):
    if lang not in _parsers:
        try:
            _parsers[lang] = get_parser(lang)
        except Exception:
            _parsers[lang] = None
    return _parsers[lang]


def _node_name(node) -> str:
    name = node.child_by_field_name("name")
    if name is None:
        for c in node.children:
            if c.type in ("identifier", "type_identifier", "property_identifier", "field_identifier"):
                name = c
                break
    return name.text.decode(errors="replace") if name is not None else "<anonymous>"


def _walk(node, out, src_lines, parent_class=None):
    for child in node.children:
        t = child.type
        if t in CLASS_TYPES:
            name = _node_name(child)
            out["classes"].append({"name": name, "start": child.start_point[0] + 1, "end": child.end_point[0] + 1})
            _walk(child, out, src_lines, parent_class=name)
            continue
        if t in FUNCTION_TYPES:
            name = _node_name(child)
            params = child.child_by_field_name("parameters")
            out["functions"].append({
                "name": f"{parent_class}.{name}" if parent_class else name,
                "params": params.text.decode(errors="replace") if params is not None else "",
                "start": child.start_point[0] + 1,
                "end": child.end_point[0] + 1,
            })
        elif t in IMPORT_TYPES:
            out["imports"].append(child.text.decode(errors="replace").strip()[:200])
        _walk(child, out, src_lines, parent_class)


def parse_file(lang: str, text: str) -> dict:
    out = {"classes": [], "functions": [], "imports": []}
    p = _parser(lang)
    if p is None:
        return out
    tree = p.parse(text.encode())
    _walk(tree.root_node, out, text.splitlines())
    return out


def _module_keys(rel: str):
    """Names other files might use to import this file."""
    p = PurePosixPath(rel)
    no_ext = str(p.with_suffix(""))
    keys = {no_ext.replace("/", "."), p.stem}
    if p.stem in ("__init__", "index"):
        keys.add(str(p.parent).replace("/", "."))
        keys.add(p.parent.name)
    return {k for k in keys if k and k != "."}


def _resolve_imports(files: dict) -> list:
    key_to_file = {}
    for rel in files:
        for k in _module_keys(rel):
            key_to_file.setdefault(k, rel)
    edges = set()
    for rel, info in files.items():
        for imp in info["imports"]:
            tokens = set(re.findall(r"[\w./-]+", imp))
            for tok in tokens:
                cand = tok.strip("./").replace("/", ".")
                for c in (cand, cand.split(".")[-1]):
                    target = key_to_file.get(c)
                    if target and target != rel:
                        edges.add((rel, target))
                        break
    return sorted(edges)


def _mermaid(edges, files) -> str:
    ids = {f: f"n{i}" for i, f in enumerate(sorted(files))}
    lines = ["graph LR"]
    used = {f for e in edges for f in e} or set(list(sorted(files))[:30])
    for f in sorted(used):
        lines.append(f'    {ids[f]}["{f}"]')
    for a, b in edges:
        lines.append(f"    {ids[a]} --> {ids[b]}")
    return "\n".join(lines)


def _folder_tree(paths, limit=200) -> str:
    tree = {}
    for p in paths[:limit]:
        node = tree
        for part in p.split("/"):
            node = node.setdefault(part, {})
    lines = []

    def rec(node, prefix=""):
        items = sorted(node.items(), key=lambda kv: (not kv[1], kv[0]))
        for i, (name, child) in enumerate(items):
            last = i == len(items) - 1
            lines.append(f"{prefix}{'└── ' if last else '├── '}{name}{'/' if child else ''}")
            rec(child, prefix + ("    " if last else "│   "))

    rec(tree)
    return "\n".join(lines)


def analyze_structure(root: Path) -> dict:
    files, chunks = {}, []
    langs = Counter()
    total_lines = 0
    for rel, lang, text in iter_source_files(root):
        info = parse_file(lang, text)
        lines = text.splitlines()
        info.update(language=lang, lines=len(lines))
        files[rel] = info
        langs[lang] += len(lines)
        total_lines += len(lines)
        symbols = info["functions"] + info["classes"]
        for s in symbols:
            body = "\n".join(lines[s["start"] - 1 : s["end"]])
            chunks.append({"id": f"{rel}:{s['start']}", "file": rel, "symbol": s["name"],
                           "start": s["start"], "end": s["end"], "text": body[:6000]})
        if not symbols:
            for i in range(0, max(len(lines), 1), 80):
                chunks.append({"id": f"{rel}:{i + 1}", "file": rel, "symbol": None, "start": i + 1,
                               "end": min(i + 80, len(lines)), "text": "\n".join(lines[i : i + 80])[:6000]})
    edges = _resolve_imports(files)
    return {
        "summary": {
            "files": len(files), "lines": total_lines, "languages": dict(langs),
            "classes": sum(len(f["classes"]) for f in files.values()),
            "functions": sum(len(f["functions"]) for f in files.values()),
        },
        "files": files,
        "dependencies": [{"from": a, "to": b} for a, b in edges],
        "mermaid": _mermaid(edges, files),
        "tree": _folder_tree(sorted(files)),
        "chunks": chunks,
    }
