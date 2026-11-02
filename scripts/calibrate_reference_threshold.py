"""Калибровка порога сравнения с эталонным фото (ReferenceStore.SIMILARITY_THRESHOLD в Android-версии).

Та же модель MobileNet V3 small, что в приложении. Сравнивает фото коврика с его искажёнными
копиями (поворот, кадр, свет, размытие) и с посторонними изображениями.

    pip install mediapipe pillow
    python scripts/calibrate_reference_threshold.py android/app/build/generated/models/image_embedder.tflite         design/rug_source.jpg "path/to/other/images/*.png"
"""
import glob
import sys

import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
from PIL import Image, ImageEnhance, ImageFilter

MODEL, RUG = sys.argv[1], sys.argv[2]
embedder = vision.ImageEmbedder.create_from_options(
    vision.ImageEmbedderOptions(base_options=mpt.BaseOptions(model_asset_path=MODEL), l2_normalize=True)
)


def emb(img: Image.Image):
    arr = np.asarray(img.convert("RGB"))
    return embedder.embed(mp.Image(image_format=mp.ImageFormat.SRGB, data=arr)).embeddings[0]


def sim(a, b):
    return vision.ImageEmbedder.cosine_similarity(a, b)


rug = Image.open(RUG).convert("RGB")
rug.thumbnail((1024, 1024))
ref = emb(rug)
w, h = rug.size
positives = {
    "crop70": rug.crop((int(w * .15), int(h * .15), int(w * .85), int(h * .85))),
    "crop50-corner": rug.crop((0, 0, w // 2, h // 2)),
    "rot12": rug.rotate(12, expand=True, fillcolor=(90, 80, 70)),
    "dark": ImageEnhance.Brightness(rug).enhance(0.55),
    "bright": ImageEnhance.Brightness(rug).enhance(1.4),
    "blur": rug.filter(ImageFilter.GaussianBlur(3)),
    "small": rug.resize((w // 4, h // 4)),
    "warm": ImageEnhance.Color(rug).enhance(1.5),
    "persp": rug.transform((w, h), Image.QUAD, (w * .1, 0, 0, h, w, h, w * .9, 0)),
}
print("POSITIVES")
for name, img in positives.items():
    print(f"  {sim(ref, emb(img)):.3f} {name}")
print("NEGATIVES")
negatives = sys.argv[3:]
scores = []
for path in negatives:
    for p in glob.glob(path):
        try:
            s = sim(ref, emb(Image.open(p)))
        except Exception:  # noqa: BLE001 — нечитаемые файлы пропускаем
            continue
        scores.append((s, p))
for s, p in sorted(scores, reverse=True)[:12]:
    print(f"  {s:.3f} {p[-60:]}")
print("max negative", max(scores)[0] if scores else None, "count", len(scores))
