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

# Сброс коррекции
DISPLAY="${DISPLAY:-:0}" xcalib -clear 2>/dev/null || true

echo "Готово. Коррекция сброшена, сервис удалён."
