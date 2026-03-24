# brightness-gamma-fix

Автоматическая коррекция пересвета на ноутбуках при снижении яркости дисплея.

## Протестировано на

- **Ноутбук:** Lecoo N155A
- **Панель:** CSO SNE007ZA2-1 (China Star Optoelectronics), 2880x1800
- **Подсветка:** amdgpu_bl1
- **ОС:** Ubuntu 24.04 (X11)

Проблема может встречаться и на других ноутбуках с аналогичными панелями.

## Проблема

Некоторые панели при снижении яркости подсветки переэкспонируют картинку — highlights слишком яркие. На максимальной яркости всё выглядит нормально. Это аппаратная особенность панели.

## Решение

Скрипт отслеживает изменение яркости и автоматически корректирует контраст через `xcalib`:

- **Максимальная яркость** — без коррекции (contrast = 100)
- **Минимальная яркость** — полная коррекция (contrast = 75)
- Плавный линейный переход по всему диапазону

Значение минимального контраста настраивается.

## Требования

- Linux с X11 (на Wayland `xcalib` не работает)
- `xcalib`
- `inotify-tools`
- `bc`

## Быстрая установка

```bash
git clone <url> && cd brightness-gamma-fix
chmod +x install.sh
./install.sh
```

Установщик автоматически:
1. Установит зависимости
2. Определит путь к подсветке
3. Спросит силу коррекции (`MIN_CONTRAST`)
4. Создаст скрипт и systemd-сервис
5. Запустит и добавит в автозагрузку

## Ручная установка

### 1. Зависимости

```bash
sudo apt install inotify-tools xcalib bc
```

### 2. Определите путь к подсветке

```bash
ls /sys/class/backlight/
# Пример: intel_backlight, amdgpu_bl1, acpi_video0

cat /sys/class/backlight/<ваш_backlight>/max_brightness
```

### 3. Подберите силу коррекции

```bash
# Применить коррекцию вручную (contrast 0–100, меньше = темнее highlights)
DISPLAY=:0 xcalib -gc 1.0 -co 75 -alter

# Сбросить
DISPLAY=:0 xcalib -clear
```

### 4. Установите скрипт

```bash
cp brightness-gamma-fix.sh ~/.local/bin/
chmod +x ~/.local/bin/brightness-gamma-fix.sh
```

Отредактируйте `~/.local/bin/brightness-gamma-fix.sh` — задайте `BACKLIGHT`, `MAX`, `MIN_CONTRAST` под свою систему.

### 5. Создайте systemd-сервис

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/brightness-gamma-fix.service << 'EOF'
[Unit]
Description=Auto-adjust contrast based on brightness

[Service]
Type=simple
ExecStart=/bin/bash -c 'inotifywait -m -e modify /sys/class/backlight/YOUR_BACKLIGHT/brightness | while read; do ~/.local/bin/brightness-gamma-fix.sh; done'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
```

Замените `YOUR_BACKLIGHT` на ваш (например `amdgpu_bl1` или `intel_backlight`).

### 6. Запустите

```bash
systemctl --user daemon-reload
systemctl --user enable --now brightness-gamma-fix.service
```

## Переключение на X11

Коррекция работает только в X11. Если вы на Wayland (по умолчанию в Ubuntu 22.04+):

1. Выйдите из сессии (Log Out)
2. На экране входа нажмите шестерёнку
3. Выберите **"Ubuntu on Xorg"**
4. Войдите

GDM запомнит выбор и будет запускать X11 по умолчанию.

## Управление

```bash
# Статус
systemctl --user status brightness-gamma-fix.service

# Остановить
systemctl --user stop brightness-gamma-fix.service

# Перезапустить (после изменения настроек)
systemctl --user restart brightness-gamma-fix.service

# Отключить автозагрузку
systemctl --user disable brightness-gamma-fix.service
```

## Настройка

Параметры в файле `~/.local/bin/brightness-gamma-fix.sh`:

| Параметр | По умолчанию | Описание |
|---|---|---|
| `BACKLIGHT` | `/sys/class/backlight/amdgpu_bl1/brightness` | Путь к файлу яркости |
| `MAX` | `255` | Максимальная яркость |
| `MIN_CONTRAST` | `75` | Контраст при минимальной яркости (0–100) |

Параметры также можно передать через переменные окружения.

## Удаление

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Как это работает

1. `inotifywait` следит за изменениями файла яркости
2. При каждом изменении запускается скрипт
3. Скрипт читает текущую яркость и вычисляет контраст линейно: `contrast = MIN_CONTRAST + (brightness/MAX) * (100 - MIN_CONTRAST)`
4. `xcalib -clear` сбрасывает LUT, затем `xcalib -co <contrast> -alter` применяет новое значение

Сброс перед применением (`-clear` + `-alter`) нужен, чтобы избежать накопления коррекции при быстром изменении яркости.

```
Контраст
100% ┤╮
     │ ╲
 75% ┤  ╲──────────────────────────
     │
     └──┬───┬───┬───┬── Яркость
        0%  25% 50% 75% 100%
```
