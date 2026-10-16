"""Генерация звуков и иконки для Sajda. Запуск: python gen_assets.py <project_root>"""
import json
import math
import os
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = sys.argv[1]
APP = os.path.join(ROOT, "Sajda")
SR = 22050


# ---------------------------------------------------------------- sounds
def write_wav(path, samples):
    samples = np.clip(samples, -1, 1)
    data = (samples * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def normalize(x, peak=0.97):
    x = np.tanh(x * 1.6)  # мягкое ограничение = громче на слух
    return x / np.max(np.abs(x)) * peak


def envelope(n, attack=0.005, release=0.02):
    env = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    env[:a] = np.linspace(0, 1, a)
    env[-r:] = np.linspace(1, 0, r)
    return env


def tone(freq, dur, harmonics=(1, 0.5, 0.3)):
    t = np.arange(int(dur * SR)) / SR
    s = sum(a * np.sin(2 * math.pi * freq * (i + 1) * t) for i, a in enumerate(harmonics))
    return s * envelope(len(t))


def pulse(total=28.0):
    out = []
    beep = np.concatenate([tone(1760, 0.09), np.zeros(int(0.05 * SR))])
    group = np.concatenate([beep] * 4 + [np.zeros(int(0.35 * SR))])
    while sum(map(len, out)) < total * SR:
        out.append(group)
    return normalize(np.concatenate(out)[: int(total * SR)])


def bell(total=28.0):
    t = np.arange(int(1.4 * SR)) / SR
    partials = [(880, 1.0), (1760, 0.6), (2637, 0.4), (3520, 0.25), (1320, 0.3)]
    strike = sum(a * np.sin(2 * math.pi * f * t) * np.exp(-t * (2.5 + f / 1500)) for f, a in partials)
    strike2 = np.roll(strike, int(0.0)) * 0.9
    phrase = np.concatenate([strike[: int(0.45 * SR)], strike2[: int(0.45 * SR)], strike])
    reps = int(total * SR / len(phrase)) + 1
    return normalize(np.tile(phrase, reps)[: int(total * SR)])


def siren(total=28.0):
    t = np.arange(int(total * SR)) / SR
    freq = 900 + 500 * np.sin(2 * math.pi * 0.9 * t)
    phase = 2 * math.pi * np.cumsum(freq) / SR
    s = np.sin(phase) + 0.4 * np.sin(2 * phase) + 0.2 * np.sign(np.sin(phase))
    return normalize(s)


def gen_sounds():
    out_dir = os.path.join(APP, "Resources", "Sounds")
    os.makedirs(out_dir, exist_ok=True)
    write_wav(os.path.join(out_dir, "alarm_pulse.wav"), pulse())
    write_wav(os.path.join(out_dir, "alarm_bell.wav"), bell())
    write_wav(os.path.join(out_dir, "alarm_siren.wav"), siren())
    write_wav(os.path.join(out_dir, "silence.wav"), np.zeros(SR * 2))


# ---------------------------------------------------------------- icon
def hexc(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4)) + (a,)


def star8(draw, cx, cy, r, fill=None, outline=None, width=1):
    for rot in (0, 45):
        pts = []
        for k in range(4):
            ang = math.radians(rot + 90 * k + 45)
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
        draw.polygon(pts, fill=fill, outline=outline, width=width)


def diamond(draw, cx, cy, rx, ry, fill=None, outline=None, width=1):
    draw.polygon([(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)], fill=fill, outline=outline, width=width)


def pointed_arch(x0, x1, y_spring, y_bottom, steps=80):
    """Стрельчатая арка: две дуги, пересекающиеся над центром."""
    r = (x1 - x0) * 0.85
    cx = (x0 + x1) / 2
    center_x = x0 + r  # центр левой дуги лежит справа от её начала
    theta_apex = math.acos((cx - center_x) / r)
    left = []
    for i in range(steps + 1):
        th = math.pi + (theta_apex - math.pi) * i / steps
        left.append((center_x + r * math.cos(th), y_spring - r * math.sin(th)))
    right = [(2 * cx - x, y) for x, y in reversed(left)]
    return [(x0, y_bottom)] + left + right[1:] + [(x1, y_bottom)]


def rug_texture(p):
    """Плоский рисунок саджады. p — палитра."""
    W, H, F = 1200, 1700, 70  # F — бахрома сверху/снизу
    img = Image.new("RGBA", (W, H + 2 * F), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # бахрома
    for x in range(24, W - 16, 22):
        d.line([(x, 4), (x, F + 6)], fill=p["fringe"], width=8)
        d.line([(x, H + F - 6), (x, H + 2 * F - 4)], fill=p["fringe"], width=8)

    top = F
    d.rectangle([0, top, W, top + H], fill=p["border"])
    B = 120
    # линии бордюра
    d.rectangle([18, top + 18, W - 18, top + H - 18], outline=p["line"], width=8)
    d.rectangle([B - 14, top + B - 14, W - B + 14, top + H - B + 14], outline=p["line"], width=8)
    # орнамент бордюра — ромбы
    step = 92
    for x in range(B, W - B + 1, step):
        diamond(d, x, top + B / 2 + 4, 26, 30, fill=p["motif"])
        diamond(d, x, top + H - B / 2 - 4, 26, 30, fill=p["motif"])
    for y in range(top + B + 40, top + H - B, step):
        diamond(d, B / 2 + 4, y, 30, 26, fill=p["motif"])
        diamond(d, W - B / 2 - 4, y, 30, 26, fill=p["motif"])

    # поле
    fx0, fy0, fx1, fy1 = B + 10, top + B + 10, W - B - 10, top + H - B - 10
    d.rectangle([fx0, fy0, fx1, fy1], fill=p["field"])

    # михраб (арка)
    ax0, ax1 = fx0 + 70, fx1 - 70
    spring = fy0 + 560
    arch = pointed_arch(ax0, ax1, spring, fy1 - 70)
    d.polygon(arch, fill=p["arch"])
    d.line(arch + [arch[0]], fill=p["line"], width=12, joint="curve")

    # звёзды в «плечах» над аркой
    star8(d, fx0 + 95, fy0 + 95, 46, fill=p["motif"])
    star8(d, fx1 - 95, fy0 + 95, 46, fill=p["motif"])

    # медальон-звезда в арке
    mcx, mcy = (fx0 + fx1) / 2, spring + 120
    star8(d, mcx, mcy, 150, outline=p["line"], width=12)
    star8(d, mcx, mcy, 70, fill=p["motif"])

    # ряд ромбов у основания арки
    for i in range(5):
        cx = ax0 + 90 + i * (ax1 - ax0 - 180) / 4
        diamond(d, cx, fy1 - 190, 34, 52, outline=p["line"], width=8)
    return img


def perspective_coeffs(dst, src):
    """Коэффициенты PIL PERSPECTIVE: dst (выходные точки) -> src (точки текстуры)."""
    m, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        b += [u, v]
    return np.linalg.solve(np.array(m, float), np.array(b, float)).tolist()


def rug_from_photo(path, fringe):
    """Текстура из фото коврика + бахрома сверху и снизу."""
    from PIL import ImageEnhance
    photo = Image.open(path).convert("RGBA")
    W = 1200
    H = int(photo.height * W / photo.width)
    photo = photo.resize((W, H), Image.LANCZOS)
    photo = ImageEnhance.Contrast(photo).enhance(1.08)
    photo = ImageEnhance.Color(photo).enhance(1.1)
    F = 70
    img = Image.new("RGBA", (W, H + 2 * F), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x in range(24, W - 16, 22):
        d.line([(x, 4), (x, F + 6)], fill=fringe, width=8)
        d.line([(x, H + F - 6), (x, H + 2 * F - 4)], fill=fringe, width=8)
    img.alpha_composite(photo, (0, F))
    return img


PHOTO = None


def compose_icon(palette, background, shadow_alpha, size=2048):
    tex = rug_from_photo(PHOTO, palette["fringe"]) if PHOTO else rug_texture(palette)
    tw, th = tex.size
    s = size / 1024
    quad = [(262 * s, 100 * s), (752 * s, 146 * s), (852 * s, 918 * s), (160 * s, 878 * s)]
    src = [(0, 0), (tw, 0), (tw, th), (0, th)]
    warped = tex.transform((size, size), Image.PERSPECTIVE, perspective_coeffs(quad, src), Image.BICUBIC)

    canvas = Image.new("RGBA", (size, size), background)
    if shadow_alpha:
        alpha = warped.split()[3].point(lambda a: int(a * shadow_alpha))
        shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        shadow.putalpha(alpha)
        shadow = shadow.transform((size, size), Image.AFFINE, (1, 0, -14 * s, 0, 1, -26 * s))
        shadow = shadow.filter(ImageFilter.GaussianBlur(28 * s))
        canvas = Image.alpha_composite(canvas, shadow)
    canvas = Image.alpha_composite(canvas, warped)
    return canvas.resize((1024, 1024), Image.LANCZOS)


LIGHT = {
    "border": hexc("#123F2E"), "field": hexc("#1D6347"), "arch": hexc("#164E38"),
    "line": hexc("#E6D6A8"), "motif": hexc("#C9A95C"), "fringe": hexc("#CDB98A"),
}
DARK = {
    "border": hexc("#17533C"), "field": hexc("#23775A"), "arch": hexc("#1B6247"),
    "line": hexc("#EFE2BC"), "motif": hexc("#D6B76A"), "fringe": hexc("#F2EAD5"),
}


def gen_icons():
    assets = os.path.join(APP, "Resources", "Assets.xcassets")
    icon_dir = os.path.join(assets, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    light = compose_icon(LIGHT, hexc("#F1EBDD"), 0.22)
    light.convert("RGB").save(os.path.join(icon_dir, "AppIcon.png"))

    dark = compose_icon(DARK, (0, 0, 0, 0), 0.0)
    dark.save(os.path.join(icon_dir, "AppIcon-Dark.png"))

    tinted_src = compose_icon(DARK, (0, 0, 0, 0), 0.0)
    gray = tinted_src.convert("LA")
    lum = np.array(gray.split()[0], dtype=float)
    lum = np.clip((lum - lum.min()) / max(1, lum.max() - lum.min()) * 255 * 1.15, 0, 255).astype("uint8")
    tinted = Image.merge("RGBA", [Image.fromarray(lum)] * 3 + [gray.split()[1]])
    black = Image.new("RGBA", (1024, 1024), (0, 0, 0, 255))
    Image.alpha_composite(black, tinted).convert("RGB").convert("L").save(os.path.join(icon_dir, "AppIcon-Tinted.png"))

    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        json.dump({
            "images": [
                {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
                {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-Dark.png",
                 "idiom": "universal", "platform": "ios", "size": "1024x1024"},
                {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-Tinted.png",
                 "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            ],
            "info": {"author": "xcode", "version": 1},
        }, f, indent=2)

    mark_dir = os.path.join(assets, "RugMark.imageset")
    os.makedirs(mark_dir, exist_ok=True)
    light.resize((512, 512), Image.LANCZOS).save(os.path.join(mark_dir, "RugMark.png"))
    with open(os.path.join(mark_dir, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "RugMark.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)

    def colorset(name, light_rgb, dark_rgb):
        cdir = os.path.join(assets, f"{name}.colorset")
        os.makedirs(cdir, exist_ok=True)

        def comp(rgb):
            return {"color": {"color-space": "srgb", "components": {
                "red": f"{rgb[0] / 255:.3f}", "green": f"{rgb[1] / 255:.3f}", "blue": f"{rgb[2] / 255:.3f}",
                "alpha": "1.000"}}, "idiom": "universal"}

        dark_entry = comp(dark_rgb)
        dark_entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        with open(os.path.join(cdir, "Contents.json"), "w") as f:
            json.dump({"colors": [comp(light_rgb), dark_entry], "info": {"author": "xcode", "version": 1}}, f, indent=2)

    colorset("AccentColor", hexc("#1D6347"), hexc("#5FBF92"))
    colorset("LaunchBackground", hexc("#F2F2F7"), hexc("#000000"))
    with open(os.path.join(assets, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


if __name__ == "__main__":
    if len(sys.argv) > 2:
        PHOTO = sys.argv[2]
    gen_sounds()
    gen_icons()
    print("ok")
