#!/bin/bash
set -e

echo "=== Удаление brightness-gamma-fix ==="

# Остановка и удаление сервиса
systemctl --user stop brightness-gamma-fix.service 2>/dev/null || true
systemctl --user disable brightness-gamma-fix.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/brightness-gamma-fix.service"
systemctl --user daemon-reload

# Удаление скрипта
rm -f "$HOME/.local/bin/brightness-gamma-fix.sh"

# Сброс гаммы
DISPLAY_NAME=$(xrandr --listmonitors 2>/dev/null | grep -oP '\S+$' | tail -1)
if [ -n "$DISPLAY_NAME" ]; then
    xrandr --output "$DISPLAY_NAME" --gamma 1.0:1.0:1.0 2>/dev/null || true
fi

echo "Готово. Гамма сброшена, сервис удалён."
