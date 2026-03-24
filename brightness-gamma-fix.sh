#!/bin/bash
# Корректирует экспозицию дисплея в зависимости от яркости.
# 255 -> contrast = 100 (xcalib -clear)
# 0   -> contrast = 75
# Плавный линейный переход по всему диапазону.

BACKLIGHT="${BACKLIGHT:-/sys/class/backlight/amdgpu_bl1/brightness}"
MAX="${MAX:-255}"
MIN_CONTRAST="${MIN_CONTRAST:-75}"
MAX_CONTRAST=100

CUR=$(cat "$BACKLIGHT")

if [ "$CUR" -ge "$MAX" ]; then
    DISPLAY="${DISPLAY:-:0}" xcalib -clear
else
    RATIO=$(echo "scale=4; $CUR / $MAX" | bc)
    CONTRAST=$(printf "%.0f" $(echo "scale=4; $MIN_CONTRAST + $RATIO * ($MAX_CONTRAST - $MIN_CONTRAST)" | bc))
    DISPLAY="${DISPLAY:-:0}" xcalib -clear
    DISPLAY="${DISPLAY:-:0}" xcalib -gc 1.0 -co $CONTRAST -alter
fi
