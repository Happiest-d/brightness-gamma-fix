#!/bin/bash
set -e

# ── Установка brightness-gamma-fix ──

echo "=== Установка brightness-gamma-fix ==="
echo ""

# Проверка X11
if [ "$XDG_SESSION_TYPE" != "x11" ]; then
    echo "ВНИМАНИЕ: Вы не в X11-сессии (текущая: $XDG_SESSION_TYPE)."
    echo "Коррекция гаммы через xrandr работает только в X11."
    echo "На экране входа выберите 'Ubuntu on Xorg' и повторите установку."
    echo ""
    read -p "Продолжить всё равно? (y/N): " answer
    [ "$answer" != "y" ] && exit 1
fi

# Зависимости
if ! command -v inotifywait &>/dev/null; then
    echo "Устанавливаю inotify-tools..."
    sudo apt install -y inotify-tools
fi

if ! command -v xrandr &>/dev/null; then
    echo "Устанавливаю x11-xserver-utils..."
    sudo apt install -y x11-xserver-utils
fi

# Определение дисплея и подсветки
DISPLAY_NAME=$(xrandr --listmonitors 2>/dev/null | grep -oP '\S+$' | tail -1)
BACKLIGHT_DIR=$(ls /sys/class/backlight/ 2>/dev/null | head -1)

if [ -z "$DISPLAY_NAME" ]; then
    echo "Ошибка: не удалось определить дисплей."
    exit 1
fi

if [ -z "$BACKLIGHT_DIR" ]; then
    echo "Ошибка: не найден backlight в /sys/class/backlight/."
    exit 1
fi

BACKLIGHT_PATH="/sys/class/backlight/$BACKLIGHT_DIR/brightness"
MAX_BRIGHTNESS=$(cat "/sys/class/backlight/$BACKLIGHT_DIR/max_brightness")
MID_BRIGHTNESS=$(echo "$MAX_BRIGHTNESS * 3 / 4" | bc)

echo ""
echo "Обнаружено:"
echo "  Дисплей:    $DISPLAY_NAME"
echo "  Подсветка:  $BACKLIGHT_PATH"
echo "  Макс:       $MAX_BRIGHTNESS"
echo ""

# Настройка силы коррекции по каналам
echo "Настройка коррекции по каналам (R:G:B)."
echo "Значение 1.0 = без коррекции, меньше = сильнее."
echo "По умолчанию: R=0.90, G=0.80, B=0.80"
echo ""
read -p "Коррекция красного  (0.90): " MIN_GAMMA_R
read -p "Коррекция зелёного  (0.80): " MIN_GAMMA_G
read -p "Коррекция синего    (0.80): " MIN_GAMMA_B
MIN_GAMMA_R="${MIN_GAMMA_R:-0.90}"
MIN_GAMMA_G="${MIN_GAMMA_G:-0.80}"
MIN_GAMMA_B="${MIN_GAMMA_B:-0.80}"

# Копирование скрипта
mkdir -p "$HOME/.local/bin"
SCRIPT_PATH="$HOME/.local/bin/brightness-gamma-fix.sh"

cp brightness-gamma-fix.sh "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# Подставляем значения в скрипт
sed -i "s|DISPLAY_NAME=\"\${DISPLAY_NAME:-eDP}\"|DISPLAY_NAME=\"\${DISPLAY_NAME:-$DISPLAY_NAME}\"|" "$SCRIPT_PATH"
sed -i "s|BACKLIGHT=\"\${BACKLIGHT:-/sys/class/backlight/amdgpu_bl1/brightness}\"|BACKLIGHT=\"\${BACKLIGHT:-$BACKLIGHT_PATH}\"|" "$SCRIPT_PATH"
sed -i "s|MAX=\"\${MAX:-255}\"|MAX=\"\${MAX:-$MAX_BRIGHTNESS}\"|" "$SCRIPT_PATH"
sed -i "s|MID=\"\${MID:-191}\"|MID=\"\${MID:-$MID_BRIGHTNESS}\"|" "$SCRIPT_PATH"
sed -i "s|MIN_GAMMA_R=\"\${MIN_GAMMA_R:-0.90}\"|MIN_GAMMA_R=\"\${MIN_GAMMA_R:-$MIN_GAMMA_R}\"|" "$SCRIPT_PATH"
sed -i "s|MIN_GAMMA_G=\"\${MIN_GAMMA_G:-0.80}\"|MIN_GAMMA_G=\"\${MIN_GAMMA_G:-$MIN_GAMMA_G}\"|" "$SCRIPT_PATH"
sed -i "s|MIN_GAMMA_B=\"\${MIN_GAMMA_B:-0.80}\"|MIN_GAMMA_B=\"\${MIN_GAMMA_B:-$MIN_GAMMA_B}\"|" "$SCRIPT_PATH"

echo "Скрипт установлен: $SCRIPT_PATH"

# Установка systemd-сервиса
mkdir -p "$HOME/.config/systemd/user"
SERVICE_PATH="$HOME/.config/systemd/user/brightness-gamma-fix.service"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Auto-adjust gamma based on brightness

[Service]
Type=simple
ExecStart=/bin/bash -c 'inotifywait -m -e modify $BACKLIGHT_PATH | while read; do $SCRIPT_PATH; done'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now brightness-gamma-fix.service

echo ""
echo "=== Готово! ==="
echo ""
echo "Сервис запущен и добавлен в автозагрузку."
echo "Попробуйте изменить яркость — коррекция должна применяться автоматически."
echo ""
echo "Подобрать значения вручную:"
echo "  xrandr --output $DISPLAY_NAME --gamma 0.90:0.80:0.80  # применить"
echo "  xrandr --output $DISPLAY_NAME --gamma 1.0:1.0:1.0     # сбросить"
echo ""
echo "Управление:"
echo "  systemctl --user status brightness-gamma-fix.service"
echo "  systemctl --user restart brightness-gamma-fix.service"
echo "  systemctl --user stop brightness-gamma-fix.service"
