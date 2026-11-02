"""Генерирует android/.../core/Surah.kt из Sajda/Recitation/Surah.swift — тексты сур в одном источнике.

Запуск из корня репозитория: python scripts/gen_android_surahs.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Sajda/Recitation/Surah.swift"
KOTLIN = ROOT / "android/app/src/main/java/com/prayforever/app/core/Surah.kt"

AYAH = re.compile(
    r'Ayah\(number: (\d+), arabic: "([^"]*)",\s*latin: "([^"]*)",\s*cyrillic: "([^"]*)"\)'
)
BASMALA = re.compile(
    r'static let basmala = Ayah\(number: 0,\s*arabic: "([^"]*)",\s*latin: "([^"]*)",\s*cyrillic: "([^"]*)"\)'
)


def number_of(source: str, key: str) -> int:
    match = re.search(rf"case \.{key}: return (\d+)", source)
    return int(match.group(1))


def arabic_name(source: str, key: str) -> str:
    block = source[source.index("var arabicName: String {"):]
    return re.search(rf'case \.{key}: return "([^"]*)"', block).group(1)


def ayat(source: str, key: str):
    start = source.index(f"private static let {key}Ayat = [")
    block = source[start:source.index("\n    ]", start)]
    result = []
    if "basmala.renumbered(1)" in block:
        result.append(None)
    result += AYAH.findall(block)
    return result


def kotlin_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") + '"'


def main() -> None:
    source = SWIFT.read_text(encoding="utf-8")
    keys = re.search(r"case (fatiha, [a-z, ]+)\n", source).group(1).split(", ")
    basmala = BASMALA.search(source).groups()

    lines = [
        "package com.prayforever.app.core",
        "",
        "/**",
        " * Один аят: арабский текст с огласовками (хафс) и транскрипция.",
        " * Транскрипция пословная: n-е слово через пробел соответствует n-му арабскому слову.",
        " */",
        "data class Ayah(",
        "    val number: Int,",
        "    val arabic: String,",
        "    val latin: String,",
        "    val cyrillic: String,",
        ") {",
        '    val arabicWords: List<String> get() = arabic.split(" ")',
        "",
        "    /** Кириллица для русского интерфейса, латиница для остальных. */",
        "    fun transliteration(russian: Boolean): String = if (russian) cyrillic else latin",
        "",
        '    fun transliterationWords(russian: Boolean): List<String> = transliteration(russian).split(" ")',
        "}",
        "",
        "/**",
        " * Короткие суры, которые можно прочитать после фото. Сгенерировано из `Sajda/Recitation/Surah.swift`",
        " * скриптом scripts/gen_android_surahs.py; `SurahParityTest` проверяет, что тексты совпадают.",
        " */",
        "enum class Surah(",
        "    val key: String,",
        "    val number: Int,",
        "    val arabicName: String,",
        ") {",
    ]
    for key in keys:
        lines.append(f'    {key.upper()}("{key}", {number_of(source, key)}, "{arabic_name(source, key)}"),')
    lines += [
        "    ;",
        "",
        "    /** В аль-Фатихе басмала — первый аят, в остальных сурах она показывается отдельно и не проверяется. */",
        "    val showsBasmala: Boolean get() = this != FATIHA",
        "",
        "    val ayat: List<Ayah>",
        "        get() =",
        "            when (this) {",
    ]
    lines += [f"                {key.upper()} -> {key.upper()}_AYAT" for key in keys]
    lines += [
        "            }",
        "",
        "    companion object {",
        "        val BASMALA =",
        "            Ayah(",
        "                number = 0,",
        f"                arabic = {kotlin_string(basmala[0])},",
        f"                latin = {kotlin_string(basmala[1])},",
        f"                cyrillic = {kotlin_string(basmala[2])},",
        "            )",
    ]
    for key in keys:
        lines += ["", f"        private val {key.upper()}_AYAT =", "            listOf("]
        for ayah in ayat(source, key):
            if ayah is None:
                lines.append("                BASMALA.copy(number = 1),")
                continue
            number, arabic, latin, cyrillic = ayah
            lines += [
                "                Ayah(",
                f"                    {number},",
                f"                    {kotlin_string(arabic)},",
                f"                    {kotlin_string(latin)},",
                f"                    {kotlin_string(cyrillic)},",
                "                ),",
            ]
        lines.append("            )")
    lines += ["    }", "}", ""]
    KOTLIN.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{KOTLIN.relative_to(ROOT)}: {len(keys)} surahs")


if __name__ == "__main__":
    main()
