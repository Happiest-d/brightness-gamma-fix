# brightness-gamma-fix

Автоматическая коррекция цветопередачи на ноутбуках при снижении яркости дисплея.

## Протестировано на

- **Ноутбук:** Lecoo N155A
- **Панель:** CSO SNE007ZA2-1 (China Star Optoelectronics), 2880x1800
- **Подсветка:** amdgpu_bl1
- **ОС:** Ubuntu 24.04 (X11)

Проблема может встречаться и на других ноутбуках с аналогичными панелями.

## Проблема

Некоторые панели ноутбуков (например CSO SNE007ZA2-1 от China Star Optoelectronics) при снижении яркости подсветки дают заметный сдвиг цветопередачи — кислотный зелёный и перенасыщенный синий. Это аппаратная особенность панели, проявляется и на Linux, и на Windows.

## Решение

Скрипт отслеживает изменение яркости и автоматически корректирует гамму всех трёх каналов (R, G, B) через `xrandr`:

- **Максимальная яркость** — без коррекции (1.0:1.0:1.0)
- **75%–100%** — плавное нарастание коррекции
- **Ниже 75%** — полная коррекция (0.90:0.80:0.80)

Значения настраиваются.

## Требования

- Linux с X11 (на Wayland `xrandr --gamma` не работает)
- `xrandr` (обычно предустановлен)
- `inotify-tools`
- `bc`

## Быстрая установка

```bash
git clone <url> && cd brightness-gamma-fix
chmod +x install.sh
./install.sh
```

Установщик автоматически:
1. Определит ваш дисплей и путь к подсветке
2. Установит зависимости
3. Спросит силу коррекции по каналам
4. Создаст скрипт и systemd-сервис
5. Запустит и добавит в автозагрузку

## Ручная установка

### 1. Зависимости

```bash
sudo apt install inotify-tools
```

### 2. Определите параметры дисплея

```bash
# Имя дисплея
xrandr --listmonitors
# Пример вывода: eDP, eDP-1, LVDS-1

# Путь к подсветке
ls /sys/class/backlight/
# Пример: intel_backlight, amdgpu_bl1, acpi_video0

# Максимальная яркость
cat /sys/class/backlight/<ваш_backlight>/max_brightness
```

### 3. Подберите значение коррекции

Снизьте яркость до рабочего уровня и подбирайте:

```bash
# Формат: R:G:B. Значение меньше 1.0 уменьшает канал.
# Замените eDP на ваш дисплей.

# Попробовать коррекцию всех каналов
xrandr --output eDP --gamma 0.90:0.80:0.80

# Только зелёный
xrandr --output eDP --gamma 1.0:0.85:1.0

# Сбросить
xrandr --output eDP --gamma 1.0:1.0:1.0
```

### 4. Установите скрипт

```bash
cp brightness-gamma-fix.sh ~/.local/bin/
chmod +x ~/.local/bin/brightness-gamma-fix.sh
```

Отредактируйте `~/.local/bin/brightness-gamma-fix.sh` — задайте значения `DISPLAY_NAME`, `BACKLIGHT`, `MAX`, `MID`, `MIN_GAMMA_R`, `MIN_GAMMA_G`, `MIN_GAMMA_B` под свою систему.

### 5. Создайте systemd-сервис

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/brightness-gamma-fix.service << 'EOF'
[Unit]
Description=Auto-adjust gamma based on brightness

[Service]
Type=simple
ExecStart=/bin/bash -c 'inotifywait -m -e modify /sys/class/backlight/YOUR_BACKLIGHT/brightness | while read; do %h/.local/bin/brightness-gamma-fix.sh; done'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
```

Замените `YOUR_BACKLIGHT` на ваш (например `intel_backlight` или `amdgpu_bl1`).

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

Все параметры в файле `~/.local/bin/brightness-gamma-fix.sh`:

| Параметр | По умолчанию | Описание |
|---|---|---|
| `DISPLAY_NAME` | `eDP` | Имя дисплея из `xrandr --listmonitors` |
| `BACKLIGHT` | `/sys/class/backlight/amdgpu_bl1/brightness` | Путь к файлу яркости |
| `MAX` | `255` | Максимальная яркость |
| `MID` | `191` | Порог полной коррекции (75% от MAX) |
| `MIN_GAMMA_R` | `0.90` | Коррекция красного (меньше = сильнее) |
| `MIN_GAMMA_G` | `0.80` | Коррекция зелёного (меньше = сильнее) |
| `MIN_GAMMA_B` | `0.80` | Коррекция синего (меньше = сильнее) |

Параметры также можно передать через переменные окружения.

## Удаление

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Как это работает

1. `inotifywait` следит за изменениями файла яркости в `/sys/class/backlight/`
2. При каждом изменении яркости запускается скрипт
3. Скрипт читает текущую яркость и вычисляет коэффициенты коррекции для каждого канала
4. `xrandr --gamma` применяет коррекцию к дисплею

Схема коррекции:

```
Гамма
1.0  ┤─────────────────╮
     │                  ╲  R (0.90)
0.90 ┤───────────────────╲─────
     │                  ╲
0.80 ┤───────────────────╲───── G, B (0.80)
     │
     └──┬───┬───┬───┬── Яркость
        0%  25% 50% 75% 100%
           ← полная →  ↑плавно↑ нет
```
