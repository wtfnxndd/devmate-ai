"""Secret detection: known credential formats plus high-entropy strings (like gitleaks / trufflehog).

Scans every text file (not only source code: .env, YAML, JSON, config files too). Values are masked in
results so the report itself never leaks a secret.
"""
import math
import re
from pathlib import Path

from .ingest import IGNORED_DIRS

TEXT_EXT = {
    ".py", ".js", ".jsx", ".ts", ".tsx", ".java", ".kt", ".go", ".rs", ".c", ".h", ".cpp", ".cs", ".rb", ".php",
    ".dart", ".swift", ".env", ".yml", ".yaml", ".json", ".toml", ".ini", ".cfg", ".conf", ".properties", ".xml",
    ".sh", ".bash", ".zsh", ".tf", ".gradle", ".txt", ".md", ".html", ".sql", ".pem", ".key",
}
TEXT_NAMES = {".env", ".env.local", ".env.production", ".npmrc", ".pypirc", "Dockerfile", "docker-compose.yml", "credentials"}

# (rule id, description, severity, regex). Group 1 (if any) is the secret value.
PATTERNS = [
    ("aws-access-key", "AWS access key ID", "high", r"\b((?:AKIA|ASIA)[0-9A-Z]{16})\b"),
    ("aws-secret-key", "AWS secret access key", "high", r"(?i)aws.{0,20}secret.{0,20}['\"]([A-Za-z0-9/+=]{40})['\"]"),
    ("github-token", "GitHub token", "high", r"\b((?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,})\b"),
    ("github-fine-grained", "GitHub fine-grained token", "high", r"\b(github_pat_[A-Za-z0-9_]{60,})\b"),
    ("gitlab-token", "GitLab personal access token", "high", r"\b(glpat-[A-Za-z0-9\-_]{20,})\b"),
    ("google-api-key", "Google API key", "high", r"\b(AIza[0-9A-Za-z\-_]{35})\b"),
    ("google-oauth", "Google OAuth access token", "high", r"\b(ya29\.[0-9A-Za-z\-_]{20,})\b"),
    ("slack-token", "Slack token", "high", r"\b(xox[baprs]-[0-9A-Za-z-]{10,})\b"),
    ("slack-webhook", "Slack webhook URL", "high", r"(https://hooks\.slack\.com/services/[A-Za-z0-9/]{20,})"),
    ("stripe-live-key", "Stripe live secret key", "high", r"\b((?:sk|rk)_live_[0-9A-Za-z]{20,})\b"),
    ("stripe-test-key", "Stripe test key", "low", r"\b(sk_test_[0-9A-Za-z]{20,})\b"),
    ("openai-key", "OpenAI API key", "high", r"\b(sk-(?:proj-)?[A-Za-z0-9_\-]{32,})\b"),
    ("anthropic-key", "Anthropic API key", "high", r"\b(sk-ant-[A-Za-z0-9_\-]{32,})\b"),
    ("groq-key", "Groq API key", "high", r"\b(gsk_[A-Za-z0-9]{40,})\b"),
    ("huggingface-token", "Hugging Face token", "high", r"\b(hf_[A-Za-z0-9]{30,})\b"),
    ("twilio-key", "Twilio API key", "high", r"\b(SK[0-9a-fA-F]{32})\b"),
    ("sendgrid-key", "SendGrid API key", "high", r"\b(SG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43})\b"),
    ("npm-token", "npm access token", "high", r"\b(npm_[A-Za-z0-9]{36})\b"),
    ("discord-webhook", "Discord webhook URL", "medium", r"(https://discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_\-]+)"),
    ("private-key", "Private key block", "high", r"(-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY(?: BLOCK)?-----)"),
    ("jwt", "JSON Web Token", "medium", r"\b(eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,})\b"),
    ("db-url-password", "Database URL with password", "high",
     r"((?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp)://[^\s:'\"/]+:([^\s@'\"]{3,})@[^\s'\"]+)"),
    ("password-assignment", "Hard-coded password", "medium",
     r"(?i)\b(?:password|passwd|pwd|secret|api_?key|access_?token|auth_?token)\b\s*[:=]\s*['\"]([^'\"\s]{6,})['\"]"),
]
COMPILED = [(rid, desc, sev, re.compile(rx)) for rid, desc, sev, rx in PATTERNS]

PLACEHOLDER = re.compile(r"(?i)^(x+|\*+|changeme|change_me|your[_-]?\w*|example\w*|dummy\w*|test\w*|placeholder|<[^>]+>|\$\{[^}]+\}|os\.environ.*|process\.env.*)$")
ASSIGN = re.compile(r"""(?i)\b([\w.-]*(?:key|token|secret|passw\w*|credential|auth)[\w.-]*)\b\s*[:=]\s*['"]([A-Za-z0-9+/=_\-]{20,})['"]""")


def entropy(s: str) -> float:
    if not s:
        return 0.0
    counts = {c: s.count(c) for c in set(s)}
    return -sum(n / len(s) * math.log2(n / len(s)) for n in counts.values())


def mask(v: str) -> str:
    return v[:4] + "…" + v[-2:] if len(v) > 8 else "****"


def _is_test(rel: str) -> bool:
    p = rel.lower()
    return any(x in f"/{p}" for x in ("/test/", "/tests/", "/__tests__/", "/fixtures/", "/examples/")) or "test" in p.rsplit("/", 1)[-1]


def scan(root: Path) -> dict:
    found, seen = [], set()
    files_scanned = 0
    for p in sorted(root.rglob("*")):
        if not p.is_file() or any(part in IGNORED_DIRS for part in p.relative_to(root).parts):
            continue
        if p.suffix.lower() not in TEXT_EXT and p.name not in TEXT_NAMES and not p.name.startswith(".env"):
            continue
        if p.stat().st_size > 500_000:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        files_scanned += 1
        rel = str(p.relative_to(root))
        test = _is_test(rel)
        for n, line in enumerate(text.splitlines(), 1):
            if len(line) > 2000:
                continue
            hits = []
            for rid, desc, sev, rx in COMPILED:
                m = rx.search(line)
                if m:
                    value = m.group(m.lastindex or 0) if rid != "db-url-password" else m.group(2)
                    if PLACEHOLDER.match(value):
                        continue
                    hits.append((rid, desc, sev, value))
            if not hits:
                m = ASSIGN.search(line)
                if m and entropy(m.group(2)) >= 4.0 and not PLACEHOLDER.match(m.group(2)):
                    hits.append(("high-entropy-string", f"High-entropy value assigned to '{m.group(1)}'", "medium", m.group(2)))
            for rid, desc, sev, value in hits[:1]:  # one finding per line, most specific rule first
                key = (rel, n, rid)
                if key in seen:
                    continue
                seen.add(key)
                found.append({
                    "rule": rid, "description": desc, "file": rel, "line": n,
                    "severity": "low" if test and sev != "high" else sev,
                    "in_test": test, "masked": mask(value), "entropy": round(entropy(value), 2),
                    "env_file": p.name.startswith(".env"),
                })
    order = {"high": 0, "medium": 1, "low": 2}
    found.sort(key=lambda f: (order[f["severity"]], f["file"], f["line"]))
    return {"secrets": found[:300], "files_scanned": files_scanned,
            "counts": {s: sum(1 for f in found if f["severity"] == s) for s in ("high", "medium", "low")}}


def as_findings(result: dict) -> list:
    return [{
        "tool": "devmate-secrets", "rule": f"secret-{s['rule']}", "severity": s["severity"], "category": "security",
        "owasp": "A07 Identification and Authentication Failures", "file": s["file"], "line": s["line"],
        "message": f"{s['description']} committed in source ({s['masked']}). Move it to an environment variable or secret manager and rotate it.",
    } for s in result["secrets"]]
