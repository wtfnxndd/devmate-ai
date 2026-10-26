"""Branded PDF export of any Markdown report (pure Python: fpdf2 + free DejaVu fonts)."""
import re
from datetime import datetime
from pathlib import Path

import markdown
from fpdf import FPDF
from fpdf.fonts import FontFace

FONTS = Path(__file__).parent / "fonts"
INDIGO = (99, 102, 241)
GREY = (100, 106, 120)


def _score_colour(score):
    if score is None:
        return GREY
    return (16, 185, 129) if score >= 85 else (132, 204, 22) if score >= 70 else (245, 158, 11) if score >= 55 else (239, 68, 68)


class _Doc(FPDF):
    def __init__(self, title: str):
        super().__init__(format="A4")
        self.doc_title = title
        self.add_font("DejaVu", "", FONTS / "DejaVuSans.ttf")
        self.add_font("DejaVu", "B", FONTS / "DejaVuSans-Bold.ttf")
        self.add_font("DejaVu", "I", FONTS / "DejaVuSans-Oblique.ttf")
        self.add_font("DejaVuMono", "", FONTS / "DejaVuSansMono.ttf")
        self.add_font("DejaVuMono", "B", FONTS / "DejaVuSansMono-Bold.ttf")
        self.set_auto_page_break(True, margin=18)
        self.set_margins(18, 18, 18)

    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("DejaVu", "B", 8)
        self.set_text_color(*INDIGO)
        self.cell(0, 6, "DevMate AI", new_x="LMARGIN", new_y="TOP")
        self.set_text_color(*GREY)
        self.set_font("DejaVu", "", 8)
        self.cell(0, 6, self.doc_title, align="R", new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(225, 228, 238)
        self.line(18, self.get_y() + 1, self.w - 18, self.get_y() + 1)
        self.ln(5)

    def footer(self):
        self.set_y(-12)
        self.set_font("DejaVu", "", 8)
        self.set_text_color(*GREY)
        self.cell(0, 6, f"Page {self.page_no()}/{{nb}}", align="C")


def _clean(md: str) -> str:
    # Emoji and other astral-plane characters are not in DejaVu; drop them.
    md = re.sub(r"[\U00010000-\U0010FFFF\u2600-\u27BF\u2B00-\u2BFF]", "", md)
    md = md.replace("️", "")
    # Mermaid source is unreadable in a PDF; point to the app instead.
    return re.sub(r"```mermaid\n.*?```", "_(Architecture diagram: see the Architecture tab in DevMate.)_", md, flags=re.S)


def _write(pdf, html):
    pdf.write_html(
        html,
        font_family="DejaVu",
        pre_code_font="DejaVuMono",
        tag_styles={
            "h1": FontFace(color=INDIGO, size_pt=18, emphasis="BOLD"),
            "h2": FontFace(color=INDIGO, size_pt=14, emphasis="BOLD"),
            "h3": FontFace(color=(40, 40, 60), size_pt=12, emphasis="BOLD"),
            "code": FontFace(family="DejaVuMono", color=(160, 50, 90), size_pt=9),
            "pre": FontFace(family="DejaVuMono", color=(40, 40, 60), size_pt=8, fill_color=(244, 245, 250)),
            "a": FontFace(color=INDIGO),
        },
        table_line_separators=True,
        ul_bullet_char="•",
    )


def _tables_as_text(md: str) -> str:
    """Turns Markdown tables into fixed-width code blocks."""
    def conv(m):
        rows = [[re.sub(r"[`*]", "", c).strip() for c in line.strip().strip("|").split("|")]
                for line in m.group(0).strip().splitlines()]
        rows = [r for r in rows if not all(re.fullmatch(r":?-+:?", c) for c in r)]
        widths = [max(len(r[i]) if i < len(r) else 0 for r in rows) for i in range(max(map(len, rows)))]
        lines = ["  ".join(c.ljust(widths[i]) for i, c in enumerate(r)) for r in rows]
        return "\n```\n" + "\n".join(lines) + "\n```\n"
    return re.sub(r"(?:^\|.*\|[ \t]*\n?)+", conv, md, flags=re.M)


def render(md_text: str, title: str, project: str, score=None, grade=None, _tables=True) -> bytes:
    pdf = _Doc(f"{title} · {project}")
    pdf.alias_nb_pages()
    pdf.add_page()

    # Cover band
    pdf.set_fill_color(*INDIGO)
    pdf.rect(0, 0, pdf.w, 70, "F")
    pdf.set_xy(18, 20)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("DejaVu", "B", 11)
    pdf.cell(0, 6, "DevMate AI", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("DejaVu", "B", 24)
    pdf.cell(0, 14, title, new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("DejaVu", "", 12)
    pdf.cell(0, 7, f"{project}  ·  {datetime.now():%d %B %Y}", new_x="LMARGIN", new_y="NEXT")
    if score is not None:
        pdf.set_fill_color(255, 255, 255)
        pdf.ellipse(pdf.w - 52, 17, 34, 34, "F")
        pdf.set_text_color(*_score_colour(score))
        pdf.set_font("DejaVu", "B", 18)
        pdf.set_xy(pdf.w - 52, 25)
        pdf.cell(34, 10, str(score), align="C")
        pdf.set_font("DejaVu", "", 8)
        pdf.set_xy(pdf.w - 52, 35)
        pdf.cell(34, 6, f"Grade {grade}" if grade else "score", align="C")
    pdf.set_y(82)
    pdf.set_text_color(30, 30, 40)

    html = markdown.markdown(_clean(md_text), extensions=["tables", "fenced_code", "sane_lists"])
    # HTML collapses leading spaces; keep code indentation with non-breaking spaces.
    html = re.sub(r"<pre><code[^>]*>(.*?)</code></pre>",
                  lambda m: "<pre>" + m.group(1).replace(" ", "\u00a0") + "</pre>", html, flags=re.S)
    # fpdf2 tables accept plain text only: strip inline tags (code, strong, a...) inside cells.
    html = re.sub(r"<(td|th)([^>]*)>(.*?)</\1>",
                  lambda m: f"<{m.group(1)}{m.group(2)}>{re.sub(r'<[^>]+>', '', m.group(3))}</{m.group(1)}>", html, flags=re.S)
    html = html.replace("<table>", '<table width="100%">')
    pdf.set_font("DejaVu", "", 10)
    try:
        _write(pdf, html)
    except Exception:
        # fpdf2's HTML tables are strict; on any table quirk, re-render with tables as aligned text.
        if not _tables:
            raise
        return render(_tables_as_text(md_text), title, project, score, grade, _tables=False)
    return bytes(pdf.output())
