#!/usr/bin/env bash
# Встроенные движки для macOS → app/engines/bin (их упакует .app/.dmg).
#   bash scripts/fetch-engines.sh
#
# FFmpeg и FFprobe — готовые статические сборки (npm-пакеты ffmpeg-static / ffprobe-static)
# под архитектуру машины сборки: arm64 на Apple Silicon, x64 на Intel. Без Homebrew и dylib-зависимостей.
# Фото без ImageMagick обрабатывает системный sips (JPG/PNG/HEIC/TIFF/GIF/BMP/RAW) + FFmpeg (WEBP/AVIF).
# qpdf, Poppler, ImageMagick, LibreOffice, Pandoc Morph предложит доустановить в «Компонентах» (Homebrew).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/app/engines/bin"
TMP="$(mktemp -d)"
mkdir -p "$BIN"
cd "$TMP"
npm init -y >/dev/null
npm i --no-audit --no-fund ffmpeg-static@5 ffprobe-static@3 >/dev/null
cp node_modules/ffmpeg-static/ffmpeg "$BIN/ffmpeg"
ARCH="$(uname -m)"; [ "$ARCH" = "x86_64" ] && ARCH=x64
cp "node_modules/ffprobe-static/bin/darwin/$ARCH/ffprobe" "$BIN/ffprobe" || echo "ffprobe для $ARCH не найден — прогресс видео будет без процентов"
chmod +x "$BIN"/*
# ad-hoc подпись: без неё на Apple Silicon бинарники не запустятся
codesign --force -s - "$BIN"/* || true
"$BIN/ffmpeg" -hide_banner -version | head -1 || true
"$BIN/ffprobe" -hide_banner -version 2>/dev/null | head -1 || true
du -sh "$BIN"
