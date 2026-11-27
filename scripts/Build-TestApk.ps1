[CmdletBinding()]
param(
    [Parameter(Mandatory)][uri]$GatewayUrl,
    [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if ($GatewayUrl.Scheme -notin @('http', 'https') -or $GatewayUrl.AbsolutePath -ne '/' -or $GatewayUrl.Query -or $GatewayUrl.Fragment) {
    throw 'GatewayUrl debe ser el origen del Gateway, sin /api/v1, query ni fragmento.'
}
$taskPreviousCache = $env:PUB_CACHE
Push-Location $taskRoot
try {
    # Kotlin incremental caches cannot relativize plugin sources between C: and E:.
    # Keep Pub on the project drive, without changing the user's global environment.
    $env:PUB_CACHE = Join-Path $taskRoot '.local/pub-cache'
    & (Join-Path $taskRoot 'android/gradlew.bat') --stop
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo detener el daemon Gradle antes de limpiar sus caches.' }
    & $FlutterExecutable clean
    if ($LASTEXITCODE -ne 0) { throw 'Fallo flutter clean.' }
    & $FlutterExecutable pub get
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la restauracion de dependencias.' }
    & $FlutterExecutable build apk --debug "--dart-define=API_BASE_URL=$($GatewayUrl.GetLeftPart([System.UriPartial]::Authority))"
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la compilacion Android.' }
} finally {
    $env:PUB_CACHE = $taskPreviousCache
    Pop-Location
}
