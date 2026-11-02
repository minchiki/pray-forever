"""Иконки Android из иконок iOS (тот же коврик). Запуск из корня: python design/gen_android_assets.py

AppIcon-Dark.png — коврик на прозрачном фоне: из него передний план адаптивной иконки,
монохромная иконка (Android 13+) и картинка splash-экрана. minSdk 26 — нужна только адаптивная иконка.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "Sajda/Resources/Assets.xcassets/AppIcon.appiconset"
RES = ROOT / "android/app/src/main/res"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def trimmed(image: Image.Image) -> Image.Image:
    return image.crop(image.getbbox())


def centered(content: Image.Image, canvas: int, box: float) -> Image.Image:
    """Вписывает content в квадрат box (доля canvas) по центру прозрачного холста."""
    scale = canvas * box / max(content.size)
    resized = content.resize((round(content.width * scale), round(content.height * scale)), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(resized, ((canvas - resized.width) // 2, (canvas - resized.height) // 2))
    return out


def save(image: Image.Image, folder: str, name: str) -> None:
    path = RES / folder / name
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def main() -> None:
    rug = trimmed(Image.open(ICONS / "AppIcon-Dark.png").convert("RGBA"))

    for density, factor in DENSITIES.items():
        # Адаптивная иконка 108dp: видимая область 72dp, безопасная зона 66dp.
        size = round(108 * factor)
        foreground = centered(rug, size, 0.60)
        save(foreground, f"mipmap-{density}", "ic_launcher_foreground.png")
        mono = Image.new("RGBA", foreground.size, (255, 255, 255, 0))
        mono.putalpha(foreground.getchannel("A"))
        save(mono, f"mipmap-{density}", "ic_launcher_monochrome.png")


    # Splash: значок 240dp, видимый круг 160dp — коврик вписан в него.
    save(centered(rug, 960, 0.58), "drawable-xxxhdpi", "ic_splash.png")

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        "</adaptive-icon>\n"
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = RES / "mipmap-anydpi" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(adaptive, encoding="utf-8")
    print("ok")


if __name__ == "__main__":
    main()
