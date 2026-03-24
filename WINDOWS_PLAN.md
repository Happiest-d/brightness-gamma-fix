# Windows — план реализации

## Цель

Аналог Linux-скрипта для Windows. Та же логика: при изменении яркости применяется
плавная коррекция контраста (100% → 75%).

## Результаты исследования (март 2026)

### 1. Чтение яркости

**Класс:** `WmiMonitorBrightness` в пространстве `root\wmi`
- `CurrentBrightness` — 0..100 (процент, не 0..255 как на Linux)
- `Level[]` — массив доступных уровней яркости
- Работает только для встроенного дисплея ноутбука (что и нужно)
- На десктопах без встроенного дисплея — **не работает** (класс отсутствует)

**PowerShell:**
```powershell
(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness).CurrentBrightness
```

> `Get-WmiObject` устарел в PowerShell 6+, используем `Get-CimInstance`.

### 2. Мониторинг изменений яркости

Два варианта:

| Подход | Механизм | Задержка | Примечание |
|---|---|---|---|
| `__InstanceModificationEvent` | Поллинг WMI (`WITHIN 1`) | до 1 сек | Универсальный, проверенный |
| `WmiMonitorBrightnessEvent` | Нативное WMI-событие | Мгновенно | Специализированный класс для яркости |

**Рекомендация:** использовать `WmiMonitorBrightnessEvent` — он создан специально для этого, не требует поллинга, реагирует мгновенно:

```powershell
$scope = New-Object System.Management.ManagementScope("root\wmi")
$query = New-Object System.Management.EventQuery(
    "SELECT * FROM WmiMonitorBrightnessEvent"
)
$watcher = New-Object System.Management.ManagementEventWatcher($scope, $query)
```

Свойства события: `Active` (bool), `Brightness` (uint8) — можно получить новую яркость прямо из события, без повторного запроса.

**Fallback:** если `WmiMonitorBrightnessEvent` не сработает на конкретном железе — откат на `__InstanceModificationEvent WITHIN 1 WHERE TargetInstance ISA 'WmiMonitorBrightness'`.

### 3. Установка контраста: SetDeviceGammaRamp

**API:** `SetDeviceGammaRamp` из `gdi32.dll`

**Как работает:**
- Принимает три массива по 256 значений `ushort` (R, G, B)
- `value[i] = i * (contrast/100) * 257`
  - 257 = 65535/255, нормировка на 16-битный диапазон
- При contrast=100: `value[255] = 65535` (без коррекции)
- При contrast=75: `value[255] = 49151` (75% максимума)
- R/G/B одинаковы → чистое снижение контраста без цветового сдвига

**Ограничения и подводные камни:**

1. **Эвристика безопасности.** Windows проверяет, не приведёт ли ramp к нечитаемому экрану. Если ramp слишком экстремальный — функция **молча игнорирует** его (возвращает TRUE, но ничего не делает). При contrast=75 проблемы быть не должно — это мягкая коррекция. Проблема возникает при значениях ≤ ~30%.

2. **Сброс при sleep/wake.** Gamma ramp **сбрасывается** при:
   - Выходе из спящего режима
   - Переключении пользователя
   - Отключении/подключении монитора
   - Смене разрешения

   **Решение:** скрипт и так работает в цикле WMI-событий. Нужно дополнительно:
   - Подписаться на `Win32_PowerManagementEvent` (EventType=7 = resume from suspend)
   - Или использовать таймер: переприменять коррекцию каждые 30–60 сек как подстраховку

3. **Перезапись другими приложениями.** Любое приложение может вызвать `SetDeviceGammaRamp` и перезаписать нашу коррекцию (f.lux, Night Light, игры). Периодическое переприменение решает и эту проблему.

4. **Реестровый обход эвристики** (для справки, не требуется при contrast≥50):
   ```
   HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM
   GdiIcmGammaRange = DWORD 0x00000100 (256)
   ```
   Недокументированный ключ, снимает ограничения на диапазон ramp. Требует прав администратора и перезагрузки.

### 4. Альтернативный подход: ICC-профиль с VCGT

Microsoft **рекомендует** использовать ICC-профили вместо `SetDeviceGammaRamp`:
- Создать ICC-профиль с VCGT-таблицей (аналог того, что делает xcalib на Linux)
- Загрузить через `WcsSetCalibrationManagementState` + `InstallColorProfile`
- Плюсы: персистентность, нет проблемы сброса при sleep/wake
- Минусы: сложнее реализовать в PowerShell, требует генерации ICC-файла

**Интересный факт:** `xcalib` (тот же инструмент, что используется в Linux-версии) имеет **Windows-сборку** начиная с версии 0.5. Он использует GDI для загрузки VCGT из ICC-профилей. Теоретически можно использовать `xcalib.exe` и на Windows, но это добавляет внешнюю зависимость.

**Вердикт:** начинаем с `SetDeviceGammaRamp` (проще, всё в одном скрипте), добавляем периодическое переприменение для защиты от сброса.

### 5. Execution Policy

`-ExecutionPolicy Bypass` в Task Scheduler — **нормальная практика** для локальных скриптов:
- Execution Policy — **не средство безопасности**, а защита от случайного запуска скриптов пользователем
- Microsoft прямо говорит: «пользователи могут легко обойти политику»
- Для автоматизации через Task Scheduler — стандартный подход

**Варианты для install.ps1:**
1. Запуск: `powershell -ExecutionPolicy Bypass -File install.ps1` — для установки
2. В Task Scheduler: `-WindowStyle Hidden -ExecutionPolicy Bypass -File brightness-gamma-fix.ps1`
3. Альтернатива: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` — более «чистый» подход, но требует отдельного действия от пользователя

### 6. Привилегии

| Операция | Требуется администратор? |
|---|---|
| `SetDeviceGammaRamp` | Нет |
| `Get-CimInstance WmiMonitorBrightness` | Нет |
| `WmiMonitorBrightnessEvent` watcher | Нет |
| `Register-ScheduledTask` (для текущего пользователя) | Нет |
| `GdiIcmGammaRange` реестр (если понадобится) | **Да** |

**Вывод:** весь скрипт работает без прав администратора.

## Механика

| Linux | Windows |
|---|---|
| `/sys/class/backlight/*/brightness` | WMI `WmiMonitorBrightness.CurrentBrightness` (0–100) |
| `inotifywait` | `WmiMonitorBrightnessEvent` (нативное событие) |
| `xcalib -co` | `SetDeviceGammaRamp` (GDI32) через P/Invoke |
| systemd user service | Task Scheduler (At Logon, текущий пользователь) |

## Структура проекта после рефакторинга

```
brightness-gamma-fix/
├── linux/
│   ├── brightness-gamma-fix.sh
│   ├── install.sh
│   └── uninstall.sh
├── windows/
│   ├── brightness-gamma-fix.ps1
│   ├── install.ps1
│   └── uninstall.ps1
└── README.md
```

## brightness-gamma-fix.ps1 — набросок

```powershell
# Параметры
$MIN_CONTRAST = 75
$MAX_CONTRAST = 100
$REAPPLY_INTERVAL_SEC = 60  # переприменение каждые 60 сек (защита от сброса при sleep/wake)

# P/Invoke для SetDeviceGammaRamp
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GammaRamp {
    [DllImport("gdi32.dll")]
    public static extern bool SetDeviceGammaRamp(IntPtr hDC, ref RAMP ramp);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [StructLayout(LayoutKind.Sequential)]
    public struct RAMP {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Red;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Green;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Blue;
    }
}
"@

function Set-Contrast([int]$contrast) {
    $dc = [GammaRamp]::GetDC([IntPtr]::Zero)
    $ramp = New-Object GammaRamp+RAMP
    $ramp.Red   = New-Object ushort[] 256
    $ramp.Green = New-Object ushort[] 256
    $ramp.Blue  = New-Object ushort[] 256
    for ($i = 0; $i -lt 256; $i++) {
        $val = [int]($i * ($contrast / 100.0) * 257)
        if ($val -gt 65535) { $val = 65535 }
        $ramp.Red[$i] = $ramp.Green[$i] = $ramp.Blue[$i] = [ushort]$val
    }
    [GammaRamp]::SetDeviceGammaRamp($dc, [ref]$ramp) | Out-Null
    [GammaRamp]::ReleaseDC([IntPtr]::Zero, $dc) | Out-Null
}

function Get-Brightness {
    (Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness).CurrentBrightness
}

function Apply-Correction {
    $b = Get-Brightness
    if ($b -ge 100) {
        Set-Contrast 100
    } else {
        $contrast = [int]($MIN_CONTRAST + ($b / 100.0) * ($MAX_CONTRAST - $MIN_CONTRAST))
        Set-Contrast $contrast
    }
}

# Применить сразу при запуске
Apply-Correction

# Слушать изменения яркости через нативное WMI-событие
$scope = New-Object System.Management.ManagementScope("root\wmi")
$query = New-Object System.Management.EventQuery(
    "SELECT * FROM WmiMonitorBrightnessEvent"
)
$watcher = New-Object System.Management.ManagementEventWatcher($scope, $query)

# Таймаут = REAPPLY_INTERVAL_SEC: если событий нет — переприменяем коррекцию
# (защита от сброса при sleep/wake/переключении пользователя)
$watcher.Options.Timeout = New-Object TimeSpan(0, 0, $REAPPLY_INTERVAL_SEC)
$watcher.Start()

try {
    while ($true) {
        try {
            $null = $watcher.WaitForNextEvent()
        } catch [System.Management.ManagementException] {
            # Таймаут — нормально, переприменяем коррекцию
        }
        Apply-Correction
    }
} finally {
    Set-Contrast 100   # сброс при завершении
    $watcher.Stop()
}
```

### Нюансы SetDeviceGammaRamp

- Значения ramp: `value[i] = i * (contrast/100) * 257`
  - 257 = 65535/255, нормировка на 16-битный диапазон
- При contrast=100: value[255] = 65535 (без коррекции)
- При contrast=75: value[255] = 49151 (75% максимума)
- R/G/B одинаковы — чистое снижение контраста без цветового сдвига
- **Молчаливый отказ**: если ramp слишком экстремальный, функция вернёт TRUE, но ничего не сделает
- **Сброс при sleep/wake**: решается периодическим переприменением через таймаут WMI-вотчера

### Нюансы WMI

- Namespace: `root\wmi`
- `WmiMonitorBrightnessEvent` — нативное событие, мгновенная реакция (без поллинга)
- Если не сработает на конкретном железе — fallback на `__InstanceModificationEvent WITHIN 1`
- Работает только для встроенного дисплея (что и нужно)
- На десктопах без встроенного дисплея класс `WmiMonitorBrightness` отсутствует

## install.ps1 — набросок

```powershell
# Копировать скрипт
$dest = "$env:LOCALAPPDATA\brightness-gamma-fix"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item brightness-gamma-fix.ps1 "$dest\brightness-gamma-fix.ps1"

# Зарегистрировать задачу в Task Scheduler
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\brightness-gamma-fix.ps1`""

$trigger  = New-ScheduledTaskTrigger -AtLogon
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask `
    -TaskName "brightness-gamma-fix" `
    -Action $action -Trigger $trigger -Settings $settings `
    -Force

# Запустить сразу
Start-ScheduledTask -TaskName "brightness-gamma-fix"

Write-Host "Установлено. Задача добавлена в автозагрузку."
```

## uninstall.ps1 — набросок

```powershell
Stop-ScheduledTask  -TaskName "brightness-gamma-fix" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "brightness-gamma-fix" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\brightness-gamma-fix" -ErrorAction SilentlyContinue

# TODO: сброс гаммы — нужно либо дублировать P/Invoke блок из brightness-gamma-fix.ps1,
# либо dot-source'ить общий файл. Без этого гамма зависнет после удаления.
# Set-Contrast 100
Write-Host "Удалено. Гамма сброшена."
```

## Открытые вопросы

- [ ] Проверить, работает ли `WmiMonitorBrightness` на Lecoo N155A с AMD-графикой
- [ ] Проверить `WmiMonitorBrightnessEvent` vs `__InstanceModificationEvent` — какой реально срабатывает на целевом железе
- [ ] Убедиться, что `SetDeviceGammaRamp` при contrast=75 не попадает под эвристику (ожидание: не попадает)
- [ ] Проверить сброс при sleep/wake — работает ли переприменение через таймаут WMI-вотчера
- [ ] Решить проблему сброса гаммы в uninstall.ps1 (dot-source общего файла или дублирование P/Invoke)
- [ ] Протестировать на Windows 10 и Windows 11

## Источники

- SetDeviceGammaRamp: https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-setdevicegammaramp
- WmiMonitorBrightness: https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorbrightness
- WmiMonitorBrightnessEvent: https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorbrightnessevent
- GdiIcmGammaRange workaround: https://jonls.dk/2010/09/windows-gamma-adjustments/
- xcalib (Windows): https://github.com/OpenICC/xcalib
- ICC profiles in Windows: https://learn.microsoft.com/en-us/windows/win32/wcs/advanced-color-icc-profiles
- Execution Policy: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies
- Register-ScheduledTask: https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask
