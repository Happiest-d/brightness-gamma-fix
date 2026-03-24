# Linux Mint — план реализации поддержки Wayland

## Исследование (март 2026)

### Состояние Linux Mint

**Linux Mint 22.x (текущий стабильный):**
- Cinnamon edition по умолчанию использует **X11**
- Wayland доступен как **экспериментальная** сессия — выбирается вручную на экране входа ("Cinnamon on Wayland")
- XFCE и MATE — тоже X11 по умолчанию

**Linux Mint 23 (ожидается июль–август 2026):**
- Wayland станет **поддерживаемой** (не экспериментальной) сессией
- Последний блокер (скринсейвер) решён в феврале 2026
- Станет ли Wayland дефолтом — **не решено**. Клем Лефевр: «Хотим иметь опцию на столе, но это отдельная тема»

**Вывод:** текущий скрипт с `xcalib` работает на стандартном Mint 22.x из коробки (дефолт — X11). Поддержка Wayland нужна для Mint 23+ и пользователей, переключившихся вручную.

### Зависимости скрипта от дисплейного сервера

| Компонент | Зависит от X11? |
|---|---|
| `/sys/class/backlight/*/brightness` | Нет — ядро |
| `inotifywait` | Нет — ядро (inotify) |
| `bc` | Нет |
| **`xcalib -co`** | **Да — X11 only** |
| **`DISPLAY=:0`** | **Да — X11 only** |

Единственная X11-зависимость — `xcalib` для установки контраста.

### Альтернативы xcalib для Wayland

| Инструмент | Как работает | Совместимость с Cinnamon Wayland |
|---|---|---|
| **gnome-gamma-tool** (zb3) | Создаёт ICC-профиль с VCGT-таблицей через colord. CLI, поддерживает контраст (`-c`), гамму (`-g`), per-channel RGB | **Да** — явно заявлена поддержка Cinnamon + Wayland |
| wl-gammactl | Использует протокол `wlr-gamma-control` | **Нет** — протокол wlroots, Muffin его не реализует |
| gammastep / wlsunset | Цветовая температура | Не подходит — это не контраст |

**Лучший кандидат: gnome-gamma-tool** (https://github.com/zb3/gnome-gamma-tool)
- CLI — можно вызывать из bash-скрипта
- Поддерживает контраст: `-c <float>`, где 1.0 = без коррекции
- Явно совместим с Cinnamon на Wayland
- Не конфликтует с Night Light — работает через отдельный ICC-профиль
- Лицензия: MIT

## Механика

| Linux (X11) | Linux (Wayland) |
|---|---|
| `xcalib -co $CONTRAST` | `gnome-gamma-tool -c $CONTRAST_FLOAT` |
| `xcalib -clear` | `gnome-gamma-tool -c 1.0` |
| `DISPLAY=:0` | не нужен |
| Зависимости: `xcalib` | Зависимости: `python3`, `colord` |

Маппинг контраста:
- `xcalib -co 75` (75%) → `gnome-gamma-tool -c 0.75`
- `xcalib -co 100` (сброс) → `gnome-gamma-tool -c 1.0`

## План реализации

### 1. Универсальный скрипт (X11 + Wayland)

В `brightness-gamma-fix.sh` — ветвление по `$XDG_SESSION_TYPE`:

```
if X11:
    xcalib -clear
    xcalib -gc 1.0 -co $CONTRAST -alter
if Wayland:
    gnome-gamma-tool -c $(echo "scale=2; $CONTRAST / 100" | bc)
```

### 2. Установщик

В `install.sh`:
- Добавить установку `gnome-gamma-tool` для Wayland (pip или клонирование с GitHub)
- Убрать блокирующее предупреждение о X11 — заменить на информационное
- Зависимости для Wayland: `python3`, `colord` (предустановлен в Mint Cinnamon)

### 3. Без изменений

- Мониторинг (`inotifywait`) — работает на обоих серверах
- systemd user service — не зависит от дисплейного сервера
- `/sys/class/backlight/` — ядро, не зависит от дисплейного сервера

### 4. Структура проекта

```
brightness-gamma-fix/
├── linux/
│   ├── brightness-gamma-fix.sh      # универсальный (X11 + Wayland)
│   ├── install.sh
│   └── uninstall.sh
├── windows/
│   ├── ...
└── README.md
```

## Нюансы gnome-gamma-tool

- Требует `python3` и `colord` (D-Bus сервис для управления ICC-профилями)
- `colord` предустановлен в Linux Mint Cinnamon
- Изменения через VCGT **персистентны** — переживают перезагрузку (нужен явный сброс)
- Не конфликтует с Night Light (Cinnamon 6.4+), работает через отдельный профиль

## Открытые вопросы

- **Скорость gnome-gamma-tool** — создание ICC-профиля через colord может быть медленнее прямого вызова `xcalib`. Проверить задержку при быстром изменении яркости (зажатая клавиша)
- **gnome-gamma-tool как зависимость** — сторонний Python-скрипт, не apt-пакет. Варианты:
  - (а) клонировать при установке
  - (б) встроить скрипт в проект (MIT-лицензия)
  - (в) реализовать D-Bus вызовы к colord напрямую из bash
- **Тестирование** — нужен доступ к Linux Mint с Wayland-сессией

## Источники

- gnome-gamma-tool: https://github.com/zb3/gnome-gamma-tool
- Linux Mint 23 and the Road to Wayland: https://pbxscience.com/linux-mint-23-and-the-road-to-wayland-the-final-piece-falls-into-place/
- Linux Mint's ambitious Q4 (The Register): https://www.theregister.com/2025/09/16/two_more_linux_mint_releases/
- Linux Mint Wayland Screensaver (Phoronix): https://www.phoronix.com/news/Linux-Mint-Wayland-Screensaver
- wl-gammactl: https://github.com/mischw/wl-gammactl
