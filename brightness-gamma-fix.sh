#!/bin/bash
# Корректирует гамму дисплея в зависимости от яркости.
#
# При снижении яркости подсветки некоторые панели (например CSO SNE007ZA2-1)
# дают кислотный зелёный оттенок и перенасыщенный синий. Этот скрипт
# компенсирует сдвиг цвета, корректируя все три канала гаммы
# пропорционально снижению яркости.
#
# Настройки ниже — подберите под свою панель.

# ── Настройки ──────────────────────────────────────────────
# Имя дисплея (узнать: xrandr --listmonitors)
DISPLAY_NAME="${DISPLAY_NAME:-eDP}"

# Путь к файлу яркости (узнать: ls /sys/class/backlight/)
BACKLIGHT="${BACKLIGHT:-/sys/class/backlight/amdgpu_bl1/brightness}"

# Максимальная яркость
MAX="${MAX:-255}"

# Порог яркости, ниже которого коррекция на максимуме (75% от MAX по умолчанию)
MID="${MID:-191}"

# Минимальные значения гаммы по каналам (сила коррекции)
# Чем меньше значение — тем сильнее коррекция канала.
MIN_GAMMA_R="${MIN_GAMMA_R:-0.90}"
MIN_GAMMA_G="${MIN_GAMMA_G:-0.80}"
MIN_GAMMA_B="${MIN_GAMMA_B:-0.80}"
# ──────────────────────────────────────────────────────────

CUR=$(cat "$BACKLIGHT")

if [ "$CUR" -ge "$MAX" ]; then
    GAMMA_R="1.0"
    GAMMA_G="1.0"
    GAMMA_B="1.0"
elif [ "$CUR" -le "$MID" ]; then
    GAMMA_R="$MIN_GAMMA_R"
    GAMMA_G="$MIN_GAMMA_G"
    GAMMA_B="$MIN_GAMMA_B"
else
    RATIO=$(echo "scale=4; ($CUR - $MID) / ($MAX - $MID)" | bc)
    GAMMA_R=$(echo "scale=4; $MIN_GAMMA_R + $RATIO * (1.0 - $MIN_GAMMA_R)" | bc)
    GAMMA_G=$(echo "scale=4; $MIN_GAMMA_G + $RATIO * (1.0 - $MIN_GAMMA_G)" | bc)
    GAMMA_B=$(echo "scale=4; $MIN_GAMMA_B + $RATIO * (1.0 - $MIN_GAMMA_B)" | bc)
fi

DISPLAY="${DISPLAY:-:0}" xrandr --output "$DISPLAY_NAME" --gamma "${GAMMA_R}:${GAMMA_G}:${GAMMA_B}"
