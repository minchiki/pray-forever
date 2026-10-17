#!/usr/bin/env bash
# Модель Tarteel whisper-base-ar-quran (Apache-2.0), сконвертированная в Core ML для WhisperKit.
# Ревизия закреплена, чтобы сборки были воспроизводимыми.
set -euo pipefail

REPO="aaali12/whisper-quran-coreml"
REVISION="28c1a4c7061c5cfeb407f05e12d7978ad5c8f6a5"
PREFIX="tarteel-ai_whisper-base-ar-quran"
DEST="Sajda/Resources/QuranModel"

FILES=(
  AudioEncoder.mlmodelc/analytics/coremldata.bin
  AudioEncoder.mlmodelc/coremldata.bin
  AudioEncoder.mlmodelc/metadata.json
  AudioEncoder.mlmodelc/model.mil
  AudioEncoder.mlmodelc/weights/weight.bin
  MelSpectrogram.mlmodelc/analytics/coremldata.bin
  MelSpectrogram.mlmodelc/coremldata.bin
  MelSpectrogram.mlmodelc/metadata.json
  MelSpectrogram.mlmodelc/model.mil
  MelSpectrogram.mlmodelc/weights/weight.bin
  TextDecoder.mlmodelc/analytics/coremldata.bin
  TextDecoder.mlmodelc/coremldata.bin
  TextDecoder.mlmodelc/metadata.json
  TextDecoder.mlmodelc/model.mil
  TextDecoder.mlmodelc/weights/weight.bin
  added_tokens.json
  config.json
  generation_config.json
  merges.txt
  normalizer.json
  preprocessor_config.json
  special_tokens_map.json
  tokenizer.json
  tokenizer_config.json
  vocab.json
)

for f in "${FILES[@]}"; do
  if [ -s "$DEST/$f" ]; then continue; fi
  mkdir -p "$DEST/$(dirname "$f")"
  curl -fsSL --retry 3 "https://huggingface.co/$REPO/resolve/$REVISION/$PREFIX/$f" -o "$DEST/$f"
done
du -sh "$DEST"
