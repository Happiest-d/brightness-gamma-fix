# Windows — план реализации

## Цель

Аналог Linux-скрипта для Windows. Та же логика: при изменении яркости применяется
плавная коррекция контраста (100% → 75%).

## Механика

| Linux | Windows |
|---|---|
| `/sys/class/backlight/*/brightness` | WMI `WmiMonitorBrightness.CurrentBrightness` (0–100) |
| `inotifywait` | WMI event watcher (`__InstanceModificationEvent`) |
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
    # Get-WmiObject устарел в PS 6+, используем Get-CimInstance
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

# Слушать изменения яркости через WMI
# ВАЖНО: явно указывать scope root\wmi — конструктор с одной строкой
# использует root\cimv2 по умолчанию, WmiMonitorBrightness там не существует
$scope = New-Object System.Management.ManagementScope("root\wmi")
$query = New-Object System.Management.EventQuery(
    "SELECT * FROM __InstanceModificationEvent WITHIN 1 WHERE TargetInstance ISA 'WmiMonitorBrightness'"
)
$watcher = New-Object System.Management.ManagementEventWatcher($scope, $query)
$watcher.Start()

try {
    while ($true) {
        $null = $watcher.WaitForNextEvent()
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

### Нюансы WMI

- Namespace: `root\wmi`, класс `WmiMonitorBrightness`
- `CurrentBrightness` — 0..100 (процент, не 0..255 как на Linux)
- `WITHIN 1` — опрос раз в секунду; для ноутбука достаточно
- Работает только для встроенного дисплея (что и нужно)

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

- Проверить, работает ли `WmiMonitorBrightness` на Lecoo N155A с AMD-графикой
- Убедиться, что `SetDeviceGammaRamp` не сбрасывается при смене питания (батарея/сеть)
- Нужно ли запускать install.ps1 от имени администратора?
  - `SetDeviceGammaRamp` — нет, обычный пользователь
  - `Register-ScheduledTask` — нет, для текущего пользователя
- Политика выполнения скриптов: убедиться, что `-ExecutionPolicy Bypass` достаточно
  или прописать в install.ps1 `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
