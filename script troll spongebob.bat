@echo off

if not DEFINED IS_MINIMIZED (
    set IS_MINIMIZED=1
    start "" /min "%~dpnx0" %*
    exit
)

powershell -WindowStyle Hidden -Command "Invoke-WebRequest -Uri 'https://www.myinstants.com/media/sounds/spongebob-closing-theme-song.mp3' -OutFile 'spongebob.mp3'"


echo param([int]$percent = 100)> "volumescript.ps1"
echo try {>> "volumescript.ps1"
echo     $obj = New-Object -com wscript.shell>> "volumescript.ps1"
echo     for ([int]$i = 0; $i -lt $percent; $i += 2) {>> "volumescript.ps1"
echo         $obj.SendKeys([char]175) # each tick is +2%%>> "volumescript.ps1"
echo     }>> "volumescript.ps1"
echo     exit 0 # success>> "volumescript.ps1"
echo } catch {>> "volumescript.ps1"
echo     "ERROR: $($Error[0]) (script line $($_.InvocationInfo.ScriptLineNumber))">> "volumescript.ps1"
echo     exit 1>> "volumescript.ps1"
echo }>> "volumescript.ps1"

powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File volumescript.ps1
start spongebob.mp3
exit
