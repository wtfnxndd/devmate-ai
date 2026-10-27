"""Dependency vulnerability scan (OWASP A06: Vulnerable and Outdated Components).

Reads manifest files and checks every pinned version against the free OSV.dev database
(Google's open vulnerability DB covering PyPI, npm, Pub, Go, crates.io, Maven...). No API key needed.
"""
import json
import re
import tomllib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

from .ingest import IGNORED_DIRS

OSV = "https://api.osv.dev/v1"
SEV_MAP = {"CRITICAL": "high", "HIGH": "high", "MODERATE": "medium", "MEDIUM": "medium", "LOW": "low"}


def _clean(v: str) -> str | None:
    m = re.search(r"\d+(\.\d+)*([\w.+-]*)?", v or "")
    return m.group(0) if m else None


def _requirements(text):
    for line in text.splitlines():
        m = re.match(r"\s*([A-Za-z0-9_.\-\[\]]+)\s*==\s*([\w.+-]+)", line)
        if m:
            yield re.sub(r"\[.*\]", "", m.group(1)), m.group(2)


def _package_json(text):
    data = json.loads(text)
    for key in ("dependencies", "devDependencies"):
        for name, ver in (data.get(key) or {}).items():
            v = _clean(ver)
            if v and not ver.startswith(("file:", "git", "http", "workspace:")):
                yield name, v


def _pyproject(text):
    data = tomllib.loads(text)
    deps = list(data.get("project", {}).get("dependencies", []))
    for spec in deps:
        m = re.match(r"\s*([A-Za-z0-9_.\-]+)\s*(?:\[.*\])?\s*(==|>=|~=)\s*([\w.]+)", spec)
        if m:
            yield m.group(1), m.group(3)
    for name, ver in data.get("tool", {}).get("poetry", {}).get("dependencies", {}).items():
        v = _clean(ver if isinstance(ver, str) else ver.get("version", ""))
        if name != "python" and v:
            yield name, v


def _pubspec(text):
    section = None
    for line in text.splitlines():
        if re.match(r"^(dependencies|dev_dependencies):", line):
            section = True
            continue
        if re.match(r"^\S", line):
            section = None
        m = re.match(r"^  ([a-z0-9_]+):\s*['\"]?[\^~>=]*\s*([\d.]+)", line)
        if section and m:
            yield m.group(1), m.group(2)


def _gomod(text):
    for m in re.finditer(r"^\s*(?:require\s+)?([\w./-]+\.[\w./-]+)\s+v([\w.+-]+)", text, re.M):
        yield m.group(1), m.group(2)


PARSERS = {
    "requirements.txt": ("PyPI", _requirements),
    "pyproject.toml": ("PyPI", _pyproject),
    "package.json": ("npm", _package_json),
    "pubspec.yaml": ("Pub", _pubspec),
    "go.mod": ("Go", _gomod),
}


def find_dependencies(root: Path) -> list:
    deps, seen = [], set()
    for p in sorted(root.rglob("*")):
        if not p.is_file() or any(part in IGNORED_DIRS for part in p.relative_to(root).parts):
            continue
        name = p.name
        key = "requirements.txt" if re.match(r"requirements.*\.txt$", name) else name
        if key not in PARSERS:
            continue
        eco, parse = PARSERS[key]
        try:
            for pkg, ver in parse(p.read_text(encoding="utf-8")):
                if (eco, pkg.lower(), ver) not in seen:
                    seen.add((eco, pkg.lower(), ver))
                    deps.append({"ecosystem": eco, "name": pkg, "version": ver, "manifest": str(p.relative_to(root))})
        except Exception:
            continue
    return deps


def _version_key(v: str):
    return [int(p) if p.isdigit() else -1 for p in re.split(r"[.\-+]", v)]


def _vuln_details(vid: str) -> dict:
    try:
        v = httpx.get(f"{OSV}/vulns/{vid}", timeout=20).json()
    except Exception:
        return {"id": vid}
    sev = (v.get("database_specific") or {}).get("severity", "")
    # GIT ranges hold commit hashes; only package-version ranges are useful to users.
    fixed = sorted({e["fixed"] for a in v.get("affected", []) for r in a.get("ranges", []) if r.get("type") != "GIT"
                    for e in r.get("events", []) if "fixed" in e}, key=_version_key)
    return {
        "id": vid, "aliases": [a for a in v.get("aliases", []) if a.startswith("CVE")],
        "summary": v.get("summary") or (v.get("details") or "")[:200],
        "severity": SEV_MAP.get(sev.upper(), "medium"), "fixed_in": fixed[:3],
        "url": f"https://osv.dev/vulnerability/{vid}",
    }


def scan(root: Path) -> dict:
    deps = find_dependencies(root)
    if not deps:
        return {"dependencies": [], "vulnerable": 0, "total_vulns": 0, "online": True}
    try:
        r = httpx.post(f"{OSV}/querybatch", timeout=60, json={"queries": [
            {"package": {"name": d["name"], "ecosystem": d["ecosystem"]}, "version": d["version"]} for d in deps]})
        r.raise_for_status()
        results = r.json()["results"]
    except Exception as e:
        return {"dependencies": deps, "vulnerable": 0, "total_vulns": 0, "online": False, "error": str(e)}

    ids = sorted({v["id"] for res in results for v in res.get("vulns", [])})
    with ThreadPoolExecutor(8) as pool:
        details = dict(zip(ids, pool.map(_vuln_details, ids[:150])))
    for d, res in zip(deps, results):
        d["vulns"] = [details.get(v["id"], {"id": v["id"]}) for v in res.get("vulns", [])]
        order = {"high": 0, "medium": 1, "low": 2}
        d["vulns"].sort(key=lambda x: order.get(x.get("severity"), 3))
        d["worst"] = d["vulns"][0].get("severity") if d["vulns"] else None
        # Smallest version that fixes every known vulnerability = the highest "fixed in" across them.
        fixes = [max(v["fixed_in"], key=_version_key) for v in d["vulns"] if v.get("fixed_in")]
        d["upgrade_to"] = max(fixes, key=_version_key) if fixes else None
    deps.sort(key=lambda d: (-len(d["vulns"]), d["name"].lower()))
    return {
        "dependencies": deps, "online": True,
        "vulnerable": sum(1 for d in deps if d["vulns"]),
        "total_vulns": sum(len(d["vulns"]) for d in deps),
    }


# ---------------------------------------------------------------- license compliance
DEPSDEV = {"PyPI": "pypi", "npm": "npm", "Go": "go"}
COPYLEFT_STRONG = ("AGPL", "GPL-2", "GPL-3", "GPL ", "GPLV", "SSPL", "EUPL", "OSL")
COPYLEFT_WEAK = ("LGPL", "MPL", "EPL", "CDDL", "CPL")
PERMISSIVE = ("MIT", "BSD", "APACHE", "ISC", "ZLIB", "UNLICENSE", "0BSD", "PSF", "PYTHON", "CC0", "BSL-1.0", "WTFPL", "X11")


def classify_license(lic: str | None) -> tuple[str, str]:
    """-> (risk, explanation). risk: ok | review | high | unknown"""
    if not lic:
        return "unknown", "No license found: you may not have permission to use it."
    u = lic.upper()
    if any(x in u for x in COPYLEFT_WEAK):
        return "review", "Weak copyleft: changes to this library must stay open source; usually fine to use."
    if "AGPL" in u or "SSPL" in u:
        return "high", "Network copyleft: offering the app as a service can require publishing your whole source."
    if any(x in u for x in COPYLEFT_STRONG):
        return "high", "Strong copyleft: distributing your app may require releasing your source under the same license."
    if any(x in u for x in PERMISSIVE):
        return "ok", "Permissive: free to use commercially with attribution."
    return "review", "Uncommon license: read it before shipping."


def _pypi_license(name: str, version: str) -> str | None:
    try:
        info = httpx.get(f"https://pypi.org/pypi/{name}/{version}/json", timeout=15).json()["info"]
    except Exception:
        return None
    if info.get("license_expression"):
        return info["license_expression"]
    classifiers = [c.split("::")[-1].strip() for c in info.get("classifiers", []) if c.startswith("License ::")]
    if classifiers:
        return classifiers[0].replace(" License", "")
    lic = (info.get("license") or "").strip()
    return lic.splitlines()[0][:60] if lic else None


def _license_for(dep: dict) -> str | None:
    lic = None
    system = DEPSDEV.get(dep["ecosystem"])
    if system:
        name = dep["name"].replace("/", "%2F")
        try:
            r = httpx.get(f"https://api.deps.dev/v3/systems/{system}/packages/{name}/versions/{dep['version']}", timeout=15)
            if r.status_code == 200:
                lics = [x for x in r.json().get("licenses", []) if x and x != "non-standard"]
                lic = " AND ".join(lics) or None
        except Exception:
            pass
    if not lic and dep["ecosystem"] == "PyPI":
        lic = _pypi_license(dep["name"], dep["version"])
    return lic


def add_licenses(result: dict) -> dict:
    deps = result.get("dependencies", [])
    with ThreadPoolExecutor(8) as pool:
        lics = list(pool.map(_license_for, deps))
    for d, lic in zip(deps, lics):
        d["license"] = lic
        d["license_risk"], d["license_note"] = classify_license(lic)
    result["license_counts"] = {k: sum(1 for d in deps if d.get("license_risk") == k) for k in ("ok", "review", "high", "unknown")}
    return result
