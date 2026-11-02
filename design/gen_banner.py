"""Баннеры и логотип для GitHub. Запуск из корня: python design/gen_banner.py

Идея: михраб — это и дуга дневного пути солнца. Пять намазов — точки солнца на этой дуге,
Фаджр у основания до восхода светится (это будильник). Палитра — из коврика и иконки.

Текст переводится в кривые (fontTools), поэтому SVG одинаково выглядит без установленных шрифтов.
PNG рендерится resvg. Зависимости: pip install fonttools resvg-py
Шрифты (OFL) скачиваются в design/.fonts при первом запуске.
"""
import math
import urllib.request
from pathlib import Path

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets"
FONTS = Path(__file__).resolve().parent / ".fonts"
FONT_URLS = {
    "ReemKufi.ttf": "https://github.com/google/fonts/raw/main/ofl/reemkufi/ReemKufi%5Bwght%5D.ttf",
    "GolosText.ttf": "https://github.com/google/fonts/raw/main/ofl/golostext/GolosText%5Bwght%5D.ttf",
}

NIGHT = "#0F3526"  # зелень михраба
FIELD = "#1D6347"  # поле коврика
GOLD = "#D4B26A"  # золото орнамента
MADDER = "#A3262A"  # марена коврика
PARCHMENT = "#EFE2BC"  # пергамент
MIST = "#9FB8A9"  # приглушённый текст на зелени

PRAYERS_RU = ["Фаджр", "Зухр", "Аср", "Магриб", "Иша"]


# --------------------------------------------------------------- шрифты → кривые
def font(name: str, weight: int) -> TTFont:
    path = FONTS / name
    if not path.exists():
        FONTS.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(FONT_URLS[name], path)
    return instantiateVariableFont(TTFont(path), {"wght": weight})


class Text:
    def __init__(self, ttf: TTFont):
        self.ttf = ttf
        self.glyphs = ttf.getGlyphSet()
        self.cmap = ttf.getBestCmap()
        self.upm = ttf["head"].unitsPerEm

    def width(self, text: str, size: float, tracking: float = 0) -> float:
        total = sum(self.glyphs[self.cmap[ord(c)]].width for c in text)
        return total * size / self.upm + tracking * size * (len(text) - 1)

    def path(self, text: str, size: float, x: float, y: float, tracking: float = 0, anchor: str = "start") -> str:
        """d-атрибут пути; y — базовая линия, tracking — доля кегля между буквами."""
        scale = size / self.upm
        if anchor == "middle":
            x -= self.width(text, size, tracking) / 2
        elif anchor == "end":
            x -= self.width(text, size, tracking)
        pen = SVGPathPen(self.glyphs)
        cursor = x
        for ch in text:
            name = self.cmap[ord(ch)]
            glyph = self.glyphs[name]
            glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, y)))
            cursor += glyph.width * scale + tracking * size
        return pen.getCommands()


# --------------------------------------------------------------- геометрия михраба
def arch(cx: float, width: float, spring: float, base: float):
    """Стрельчатая арка: возвращает (d пути, функция точки на контуре, y вершины)."""
    x0, x1 = cx - width / 2, cx + width / 2
    r = width * 0.85
    apex = spring - math.sqrt(r * r - (r - width / 2) ** 2)
    d = f"M{x0:.1f},{base:.1f} L{x0:.1f},{spring:.1f} A{r:.1f},{r:.1f} 0 0 1 {cx:.1f},{apex:.1f} A{r:.1f},{r:.1f} 0 0 1 {x1:.1f},{spring:.1f} L{x1:.1f},{base:.1f}"

    def on_right_arc(fraction: float):
        """Точка на правой дуге: 0 — вершина, 1 — пята арки."""
        center = (x1 - r, spring)
        a_apex = math.atan2(apex - center[1], cx - center[0])
        a_spring = 0.0
        a = a_apex + (a_spring - a_apex) * fraction
        return center[0] + r * math.cos(a), center[1] + r * math.sin(a)

    return d, on_right_arc, apex


def border_band(x: float, y: float, width: float, height: float) -> str:
    """Бордюр коврика: марена, золотые ромбы, бахрома."""
    parts = [f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{MADDER}"/>']
    parts.append(f'<rect x="{x}" y="{y + 5}" width="{width}" height="1.5" fill="{GOLD}" opacity=".7"/>')
    parts.append(f'<rect x="{x}" y="{y + height - 6.5}" width="{width}" height="1.5" fill="{GOLD}" opacity=".7"/>')
    step = height * 1.15
    cy = y + height / 2
    rx, ry = height * 0.26, height * 0.22
    i = 0
    while x + step * (i + 0.5) < x + width:
        cx = x + step * (i + 0.5)
        parts.append(f'<path d="M{cx - rx:.1f},{cy:.1f} L{cx:.1f},{cy - ry:.1f} L{cx + rx:.1f},{cy:.1f} L{cx:.1f},{cy + ry:.1f}Z" fill="{GOLD}"/>')
        i += 1
    return "".join(parts)


def mihrab_day(
    cx: float, width: float, spring: float, base: float, horizon: float, label: Text | None, label_size: float, bold: bool = False
) -> str:
    """Арка-дуга дня с пятью намазами. label=None и bold — вариант для логотипа: без подписей, крупнее линии."""
    d, on_right_arc, apex = arch(cx, width, spring, base)
    x0, x1 = cx - width / 2, cx + width / 2
    fajr = (x0, horizon + (base - horizon) * 0.32)
    isha = (x1, horizon + (base - horizon) * 0.62)
    points = [fajr, (cx, apex), on_right_arc(0.55), (x1, horizon), isha]
    uid = f"m{int(cx)}{int(width)}"
    parts = [
        "<defs>"
        f'<clipPath id="{uid}c"><path d="{d} Z"/></clipPath>'
        f'<radialGradient id="{uid}g" cx="{fajr[0] + width * 0.12:.1f}" cy="{horizon:.1f}" r="{width * 0.95:.1f}" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{GOLD}" stop-opacity=".75"/>'
        f'<stop offset=".3" stop-color="{FIELD}" stop-opacity=".7"/>'
        f'<stop offset="1" stop-color="{NIGHT}" stop-opacity="0"/></radialGradient>'
        "</defs>",
        # Небо перед рассветом внутри михраба, ниже горизонта — земля.
        f'<g clip-path="url(#{uid}c)"><rect x="{x0 - 2}" y="{apex - 2}" width="{width + 4}" height="{base - apex + 4}" fill="url(#{uid}g)"/>'
        f'<rect x="{x0 - 2}" y="{horizon:.1f}" width="{width + 4}" height="{base - horizon + 2:.1f}" fill="{NIGHT}" opacity=".55"/></g>',
        f'<line x1="{x0:.1f}" y1="{horizon:.1f}" x2="{x1:.1f}" y2="{horizon:.1f}" stroke="{GOLD}" stroke-width="1.5" opacity=".55"/>',
        f'<path d="{d}" fill="none" stroke="{GOLD}" stroke-width="{width / (26 if bold else 120):.1f}" stroke-linejoin="round"/>',
    ]
    if not bold:
        inset = width * 0.045
        d_in, _, _ = arch(cx, width - 2 * inset, spring, base)
        parts.append(f'<path d="{d_in}" fill="none" stroke="{GOLD}" stroke-width="1.2" opacity=".45"/>')
    dot = width / (16 if bold else 44)
    ring = dot / 6 if bold else 1.6
    for i, (px, py) in enumerate(points):
        if i == 0:
            # Фаджр — звонящий будильник: расходящиеся кольца.
            for k, opacity in ((3.6, 0.18), (2.6, 0.32), (1.8, 0.55)):
                parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{dot * k:.1f}" fill="none" stroke="{GOLD}" stroke-width="{ring:.1f}" opacity="{opacity}"/>')
            parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{dot * 1.15:.1f}" fill="{PARCHMENT}"/>')
        else:
            below = py > horizon + 1
            fill = NIGHT if below else GOLD
            parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{dot * 0.8:.1f}" fill="{fill}" stroke="{GOLD}" stroke-width="{ring * 1.25:.1f}"/>')
        if label is not None:
            name = PRAYERS_RU[i]
            if i == 0:
                lx, ly, anchor = px - dot * 4.4, py + label_size * 0.35, "end"
            elif i == 1:
                lx, ly, anchor = px, py - dot * 2.2, "middle"
            else:
                lx, ly, anchor = px + dot * 2.4, py + label_size * 0.35, "start"
            color = PARCHMENT if i == 0 else MIST
            parts.append(f'<path d="{label.path(name, label_size, lx, ly, 0.02, anchor)}" fill="{color}"/>')
    return "".join(parts)


# --------------------------------------------------------------- макеты
def svg(width: int, height: int, body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
        f'<rect width="{width}" height="{height}" fill="{NIGHT}"/>{body}</svg>'
    )


APEX_RATIO = math.sqrt(0.85**2 - 0.35**2)  # высота дуги над пятой в долях ширины арки


def arch_box(top: float, base: float, width: float):
    """Пята и горизонт арки заданной ширины с вершиной на высоте top."""
    spring = top + APEX_RATIO * width
    return spring, spring + (base - spring) * 0.45


def banner(width: int, height: int, kufi: Text, golos: Text, golos_medium: Text) -> str:
    band = round(height * 0.055)
    pad = round(height * 0.11)
    wide = width / height > 2.6
    base = height - band
    label = height * (0.040 if wide else 0.034)
    top = pad * 0.55 + label * 1.6
    arch_w = (base - top) / (APEX_RATIO + 0.75)
    spring, horizon = arch_box(top, base, arch_w)
    arch_cx = width - pad * 0.7 - label * 4.6 - arch_w / 2

    body = [mihrab_day(arch_cx, arch_w, spring, base, horizon, golos, label)]

    title = height * (0.30 if wide else 0.215)
    x = pad
    y = pad + title * 0.78
    body.append(f'<path d="{kufi.path("Prayer", title, x, y, -0.01)}" fill="{PARCHMENT}"/>')
    lines = (
        ["Будильник к намазу, который не замолчит, пока не", "сфотографируешь коврик и не прочитаешь суру вслух."]
        if wide
        else ["Будильник к намазу, который не замолчит,", "пока не сфотографируешь коврик", "и не прочитаешь суру вслух."]
    )
    size = height * (0.058 if wide else 0.047)
    line_y = y + title * 0.42
    for line in lines:
        line_y += size * 1.38
        body.append(f'<path d="{golos.path(line, size, x, line_y)}" fill="{MIST}"/>')
    meta = "iOS и Android. Без рекламы и аккаунтов."
    body.append(f'<path d="{golos_medium.path(meta, size * 0.78, x, base - pad * 0.62)}" fill="{GOLD}"/>')
    body.append(border_band(0, base, width, band))
    return svg(width, height, "".join(body))


def logo(size: int) -> str:
    base = size * 0.80
    top = size * 0.16
    arch_w = size * 0.50
    spring = top + APEX_RATIO * arch_w
    horizon = spring + (base - spring) * 0.40
    body = mihrab_day(size / 2, arch_w, spring, base, horizon, None, 0, bold=True)
    ground = (
        f'<line x1="{size * 0.17:.1f}" y1="{base:.1f}" x2="{size * 0.83:.1f}" y2="{base:.1f}" '
        f'stroke="{GOLD}" stroke-width="{arch_w / 26:.1f}" stroke-linecap="round"/>'
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
        f'<rect width="{size}" height="{size}" rx="{size * 0.22:.0f}" fill="{NIGHT}"/>{body}{ground}</svg>'
    )


def write(name: str, content: str, width: int, height: int) -> None:
    OUT.mkdir(exist_ok=True)
    (OUT / f"{name}.svg").write_text(content, encoding="utf-8", newline="\n")
    png = resvg_py.svg_to_bytes(svg_string=content, width=width, height=height)
    (OUT / f"{name}.png").write_bytes(bytes(png))
    print(f"assets/{name}.svg, assets/{name}.png ({width}x{height})")


def main() -> None:
    kufi = Text(font("ReemKufi.ttf", 700))
    golos = Text(font("GolosText.ttf", 400))
    golos_medium = Text(font("GolosText.ttf", 600))
    write("social-preview", banner(1280, 640, kufi, golos, golos_medium), 1280, 640)
    write("banner", banner(1600, 520, kufi, golos, golos_medium), 1600, 520)
    write("logo", logo(512), 512, 512)


if __name__ == "__main__":
    main()
