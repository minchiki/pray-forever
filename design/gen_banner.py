"""Баннеры и логотип для GitHub из оригинального дизайна приложения. Запуск из корня: python design/gen_banner.py

Образ — иконка приложения (коврик из фото на кремовом фоне), акцент — зелёный AccentColor #1D6347,
карточка ближайшего намаза как на главном экране. Заголовки — округлый шрифт, как .rounded в приложении.
Текст переводится в кривые (fontTools), поэтому SVG одинаково выглядит без установленных шрифтов.
Зависимости: pip install fonttools resvg-py pillow. Шрифт Nunito (OFL) скачивается в design/.fonts.
"""
import base64
import io
import urllib.request
from pathlib import Path

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets"
ICONS = ROOT / "Sajda/Resources/Assets.xcassets/AppIcon.appiconset"
FONTS = Path(__file__).resolve().parent / ".fonts"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/nunito/Nunito%5Bwght%5D.ttf"

CREAM = "#F1EBDD"  # фон иконки
GROUPED = "#F2F2F7"  # systemGroupedBackground
CARD = "#FFFFFF"
INK = "#10251C"
ACCENT = "#1D6347"  # AccentColor
SECONDARY = "#5B6B63"
LINE = "#E3DCC9"


def font(weight: int) -> "Text":
    path = FONTS / "Nunito.ttf"
    if not path.exists():
        FONTS.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL, path)
    return Text(instantiateVariableFont(TTFont(path), {"wght": weight}))


class Text:
    def __init__(self, ttf: TTFont):
        self.glyphs = ttf.getGlyphSet()
        self.cmap = ttf.getBestCmap()
        self.upm = ttf["head"].unitsPerEm

    def width(self, text: str, size: float) -> float:
        return sum(self.glyphs[self.cmap[ord(c)]].width for c in text) * size / self.upm

    def path(self, text: str, size: float, x: float, y: float, fill: str, anchor: str = "start") -> str:
        scale = size / self.upm
        if anchor == "end":
            x -= self.width(text, size)
        pen = SVGPathPen(self.glyphs)
        cursor = x
        for ch in text:
            glyph = self.glyphs[self.cmap[ord(ch)]]
            glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, y)))
            cursor += glyph.width * scale
        return f'<path d="{pen.getCommands()}" fill="{fill}"/>'


def rug_data_uri(px: int) -> tuple[str, tuple[int, int]]:
    """Коврик из иконки приложения на прозрачном фоне."""
    image = Image.open(ICONS / "AppIcon-Dark.png").convert("RGBA")
    image = image.crop(image.getbbox())
    image.thumbnail((px, px), Image.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode(), image.size


def prayer_card(x: float, y: float, w: float, bold: Text, regular: Text, scale: float) -> tuple[str, float]:
    """Карточка с расписанием, как «Сегодня» на главном экране. Возвращает (svg, высота)."""
    rows = [("Фаджр", "05:01"), ("Зухр", "11:27"), ("Аср", "14:06"), ("Магриб", "16:00"), ("Иша", "17:45")]
    row_h = 46 * scale
    pad = 22 * scale
    h = row_h * len(rows) + pad * 0.4
    parts = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{20 * scale}" fill="{CARD}"/>']
    for i, (name, time) in enumerate(rows):
        ry = y + pad * 0.2 + row_h * i
        active = i == 2
        color = ACCENT if active else INK
        font_ = bold if active else regular
        base = ry + row_h * 0.66
        parts.append(font_.path(name, 21 * scale, x + pad, base, color))
        parts.append(font_.path(time, 21 * scale, x + w - pad - 40 * scale, base, color, "end"))
        # колокольчик будильника — кружок акцентного цвета
        cx = x + w - pad * 0.6 - 8 * scale
        parts.append(f'<circle cx="{cx:.1f}" cy="{ry + row_h / 2:.1f}" r="{7 * scale:.1f}" fill="none" stroke="{ACCENT}" stroke-width="{2.2 * scale:.1f}"/>')
        parts.append(f'<path d="M{cx:.1f},{ry + row_h / 2 - 3 * scale:.1f} V{ry + row_h / 2:.1f} H{cx + 2.6 * scale:.1f}" fill="none" stroke="{ACCENT}" stroke-width="{1.8 * scale:.1f}" stroke-linecap="round"/>')
        if i < len(rows) - 1:
            parts.append(f'<rect x="{x + pad}" y="{ry + row_h:.1f}" width="{w - pad}" height="1" fill="{LINE}"/>')
    return "".join(parts), h


def banner(width: int, height: int, bold: Text, regular: Text, semibold: Text) -> str:
    wide = width / height > 2.6
    pad = height * 0.12
    rug_uri, (rw, rh) = rug_data_uri(900)
    rug_h = height * (0.86 if wide else 0.80)
    rug_w = rug_h * rw / rh
    rug_x = width * (0.50 if wide else 0.47)
    rug_y = (height - rug_h) / 2

    body = [f'<rect width="{width}" height="{height}" fill="{CREAM}"/>']
    # Мягкая тень под ковриком, как у иконки.
    body.append(
        f'<defs><filter id="sh" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur stdDeviation="{height * 0.03:.1f}"/></filter></defs>'
        f'<ellipse cx="{rug_x + rug_w / 2:.1f}" cy="{rug_y + rug_h * 0.96:.1f}" rx="{rug_w * 0.42:.1f}" ry="{rug_h * 0.05:.1f}" fill="#000" opacity=".22" filter="url(#sh)"/>'
        f'<image href="{rug_uri}" x="{rug_x:.1f}" y="{rug_y:.1f}" width="{rug_w:.1f}" height="{rug_h:.1f}"/>'
    )
    card_scale = height / 640 * (1.05 if wide else 0.95)
    card_w = height * (0.46 if wide else 0.42)
    card_x = width - pad - card_w
    card_svg, card_h = prayer_card(card_x, (height - 0) / 2 - 0, card_w, semibold, regular, card_scale)
    card_y = height - pad - card_h
    card_svg, card_h = prayer_card(card_x, card_y, card_w, semibold, regular, card_scale)
    body.append(card_svg)

    title = height * (0.27 if wide else 0.215)
    x = pad
    y = pad + title * 0.80
    body.append(bold.path("Prayer", title, x, y, INK))
    size = height * (0.056 if wide else 0.046)
    lines = (
        ["Будильник к намазу, который не", "замолчит, пока не сфотографируешь", "коврик и не прочитаешь суру вслух."]
        if not wide
        else ["Будильник к намазу, который не замолчит,", "пока не сфотографируешь коврик", "и не прочитаешь суру вслух."]
    )
    line_y = y + title * 0.18
    for line in lines:
        line_y += size * 1.42
        body.append(regular.path(line, size, x, line_y, SECONDARY))
    body.append(semibold.path("iOS и Android. Без рекламы и аккаунтов.", size * 0.82, x, height - pad, ACCENT))
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{"".join(body)}</svg>'


def write(name: str, content: str, width: int, height: int) -> None:
    OUT.mkdir(exist_ok=True)
    (OUT / f"{name}.svg").write_text(content, encoding="utf-8", newline="\n")
    png = resvg_py.svg_to_bytes(svg_string=content, width=width, height=height)
    (OUT / f"{name}.png").write_bytes(bytes(png))
    print(f"assets/{name}.svg, assets/{name}.png ({width}x{height})")


def main() -> None:
    bold, regular, semibold = font(800), font(500), font(700)
    write("social-preview", banner(1280, 640, bold, regular, semibold), 1280, 640)
    write("banner", banner(1600, 520, bold, regular, semibold), 1600, 520)
    # Логотип — сама иконка приложения.
    Image.open(ICONS / "AppIcon.png").convert("RGB").resize((512, 512), Image.LANCZOS).save(OUT / "logo.png", optimize=True)
    (OUT / "logo.svg").unlink(missing_ok=True)
    print("assets/logo.png (иконка приложения)")


if __name__ == "__main__":
    main()
