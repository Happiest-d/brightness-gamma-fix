#!/bin/bash
set -e

# ── Установка brightness-gamma-fix ──

echo "=== Установка brightness-gamma-fix ==="
echo ""

# Проверка X11
if [ "$XDG_SESSION_TYPE" != "x11" ]; then
    echo "ВНИМАНИЕ: Вы не в X11-сессии (текущая: $XDG_SESSION_TYPE)."
    echo "Коррекция через xcalib работает только в X11."
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

if ! command -v xcalib &>/dev/null; then
    echo "Устанавливаю xcalib..."
    sudo apt install -y xcalib
fi

if ! command -v bc &>/dev/null; then
    echo "Устанавливаю bc..."
    sudo apt install -y bc
fi

# Определение подсветки
BACKLIGHT_DIR=$(ls /sys/class/backlight/ 2>/dev/null | head -1)

if [ -z "$BACKLIGHT_DIR" ]; then
    echo "Ошибка: не найден backlight в /sys/class/backlight/."
    exit 1
fi

BACKLIGHT_PATH="/sys/class/backlight/$BACKLIGHT_DIR/brightness"
MAX_BRIGHTNESS=$(cat "/sys/class/backlight/$BACKLIGHT_DIR/max_brightness")

echo ""
echo "Обнаружено:"
echo "  Подсветка:  $BACKLIGHT_PATH"
echo "  Макс:       $MAX_BRIGHTNESS"
echo ""

# Настройка силы коррекции
echo "Минимальный контраст при минимальной яркости (0–100)."
echo "Меньше = сильнее коррекция пересвета. По умолчанию: 75"
echo ""
read -p "MIN_CONTRAST (75): " MIN_CONTRAST
MIN_CONTRAST="${MIN_CONTRAST:-75}"

# Копирование скрипта
mkdir -p "$HOME/.local/bin"
SCRIPT_PATH="$HOME/.local/bin/brightness-gamma-fix.sh"

cp brightness-gamma-fix.sh "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# Подставляем значения
sed -i "s|BACKLIGHT=\"\${BACKLIGHT:-/sys/class/backlight/amdgpu_bl1/brightness}\"|BACKLIGHT=\"\${BACKLIGHT:-$BACKLIGHT_PATH}\"|" "$SCRIPT_PATH"
sed -i "s|MAX=\"\${MAX:-255}\"|MAX=\"\${MAX:-$MAX_BRIGHTNESS}\"|" "$SCRIPT_PATH"
sed -i "s|MIN_CONTRAST=\"\${MIN_CONTRAST:-75}\"|MIN_CONTRAST=\"\${MIN_CONTRAST:-$MIN_CONTRAST}\"|" "$SCRIPT_PATH"

echo "Скрипт установлен: $SCRIPT_PATH"

# Установка systemd-сервиса
mkdir -p "$HOME/.config/systemd/user"
SERVICE_PATH="$HOME/.config/systemd/user/brightness-gamma-fix.service"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Auto-adjust contrast based on brightness

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
echo "Попробуйте изменить яркость — коррекция применяется автоматически."
echo ""
echo "Управление:"
echo "  systemctl --user status brightness-gamma-fix.service"
echo "  systemctl --user restart brightness-gamma-fix.service"
echo "  systemctl --user stop brightness-gamma-fix.service"
