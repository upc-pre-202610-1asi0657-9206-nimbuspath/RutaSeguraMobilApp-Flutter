# RutaSegura · App del Conductor

App móvil (Flutter, iOS y Android) **solo para conductores**. Se conecta al backend
[`rutasegura-backend`](https://github.com/upc-pre-202610-1asi0657-9206-nimbuspath/rutasegura-backend)
(rama `develop`) **únicamente a través del API Gateway**. El contrato está en
`docs/APP-CONDUCTOR-BACKEND.md` del backend.

## Stack

| Necesidad | Paquete |
|---|---|
| Estado / inyección | `flutter_riverpod` |
| Navegación | `go_router` |
| HTTP | `dio` |
| Token JWT | `flutter_secure_storage` (Keychain / Keystore) |
| `clientEventId`, `X-Correlation-Id` | `uuid` |

## Estructura

```text
lib/
  core/
    config/     AppConfig: URL del Gateway por entorno
    network/    ApiClient (dio), interceptores, ApiError (ProblemDetails + code)
    storage/    TokenStorage (almacenamiento seguro)
    router/     go_router
    theme/ widgets/ utils/
  iam/              login y perfil
  trip_execution/   inicio, viaje en curso, abordaje, incidente, SOS, resumen
  shell/            barra inferior Inicio / Perfil
```

## Ejecutar

1. Levantar el backend (en el repo del backend):
   ```bash
   docker compose up -d --build
   docker compose --profile smoke run --rm smoke   # crea datos de prueba
   ```
2. Ejecutar la app:

   | Dónde | Comando | URL del Gateway |
   |---|---|---|
   | Emulador Android | `flutter run --dart-define-from-file=config/dev.json` | `http://10.0.2.2:8000` (automática) |
   | Simulador iOS | `flutter run --dart-define-from-file=config/dev.json` | `http://127.0.0.1:8000` (automática) |
   | Celular físico | copiar `config/device.example.json` a `config/device.json` con la IP de tu PC, y `flutter run --dart-define-from-file=config/device.json` | `http://192.168.x.x:8000` |
   | Cualquier otra | `flutter run --dart-define=API_BASE_URL=https://...` | la indicada |

HTTP sin TLS solo está permitido en desarrollo: Android en los builds `debug`/`profile`
(`usesCleartextTraffic`), iOS solo hacia la red local (`NSAllowsLocalNetworking`).
En producción el Gateway debe ir por HTTPS.

## Cliente HTTP

- Rutas sin prefijo: `ref.read(apiClientProvider).get('/drivers/me/trips')` → `{GW}/api/v1/drivers/me/trips`.
- Agrega `Authorization: Bearer <jwt>` (salvo `auth: false`) y `X-Correlation-Id`.
- Toda falla llega como `ApiError { kind, status, code, detail, correlationId, retryAfter }`.
  **La app decide por `code`** (`ApiErrorCodes`), nunca por el texto.
- `authFailures` emite ante 401 o cuenta rechazada / empresa suspendida.
- En debug solo se registran método, ruta, estado, duración y correlación; nunca token, cuerpo ni datos de alumnos.

## Pruebas

```bash
flutter analyze
flutter test
```
