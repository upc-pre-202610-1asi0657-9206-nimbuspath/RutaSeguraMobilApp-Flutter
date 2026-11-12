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
| Caché local (agenda, último estado del viaje) | `shared_preferences` |
| Cola offline y lecturas de GPS | `sqflite` (con `path` y `path_provider`; fotos de alumnos en archivos privados) |
| GPS, con servicio en primer plano en Android | `geolocator` |
| Conectividad y batería (checklist previo y reintentos) | `connectivity_plus`, `battery_plus` |
| Mapa (OpenStreetMap) | `flutter_map`, `latlong2` |
| Tiempo real (hub del viaje) | `signalr_netcore` |
| Permiso de notificaciones (Android 13+) | `permission_handler`, fijado en `^12.0.1` (ver Pendiente) |
| Pruebas de SQLite | `sqflite_common_ffi` |

## Estructura

```text
lib/
  core/
    config/       AppConfig: URL del Gateway por entorno
    network/      ApiClient (dio), interceptores, ApiError (ProblemDetails + code), conectividad
    storage/      TokenStorage (almacenamiento seguro), caché local, fotos de alumnos
    permissions/  permiso de notificaciones
    router/       go_router
    theme/ widgets/ utils/
  iam/            login, sesión y perfil del conductor (roster, vehículos, rutas)
  stakeholder/    alumnos de las rutas del conductor y sus fotos
  trip_execution/
    application/    agenda, vigilancia de cancelaciones, viaje en curso, GPS, cola offline y sincronización
    domain/         modelos
    infrastructure/ API de viajes, canal en tiempo real (SignalR), SQLite, fuente de GPS
    presentation/   inicio, viaje en curso, abordaje, incidente, SOS, resumen y mapa
  shell/          barra inferior Inicio / Perfil
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

## Sin conexión y tiempo real

- **Sin señal.** Subió, Bajó, No vino, Deshacer, incidentes y SOS se guardan en SQLite con su
  `clientEventId` y se envían por `/trips/{id}/sync` (hasta 200 por lote) al volver la conexión; la pantalla
  los muestra como hechos y un contador indica cuántos faltan. El último estado del viaje queda en caché para
  poder abrirlo sin red. Iniciar y finalizar un viaje sí exigen conexión.
- **GPS.** Mientras el viaje está en curso se comparte la ubicación con un servicio en primer plano
  (Android). Las lecturas se guardan y se envían por lotes cada 8 s; sin señal se acumulan y salen después.
- **Tiempo real.** La app se conecta por el Gateway al hub `/hubs/trip-tracking` (SignalR, con el JWT en
  `?access_token=`) y reintenta sola. El refresco de `/live` cada 20 s queda como respaldo.
- **Avisos de la empresa.** Un viaje cancelado (el motivo llega por el hub) y un SOS resuelto se muestran en
  pantalla. El hub no informa de la resolución del SOS: se detecta por `hasActiveSos` en `/live`.
- **Agenda.** Inicio se refresca solo (cada 30 s, al volver a la app y al recuperar la conexión) y avisa si la
  empresa cancela un viaje programado.

## Pruebas

```bash
flutter analyze
flutter test
```

## Estado

La app está conectada al backend en las 8 etapas del plan. Probada en el emulador
Android contra el Gateway real (última revisión: 12/11/2026).

| Etapa | Alcance | Estado |
|---|---|---|
| 1 | Base: configuración, cliente HTTP, almacenamiento seguro, router | Hecha |
| 2 | Login y perfil | Hecha |
| 3 | Inicio y agenda, alumnos con foto, checklist previo | Hecha |
| 4 | Viaje en curso y abordaje (Subió / No vino / Deshacer) | Hecha |
| 5 | GPS en primer plano, envío por lotes | Hecha |
| 6 | Incidente, SOS, finalizar viaje y resumen | Hecha |
| 7 | Cola offline (SQLite) y `/sync` | Hecha |
| 8 | Canal en tiempo real (SignalR), avisos de la empresa, permiso de notificaciones, mapa, cancelaciones en la agenda | Hecha, con los pendientes de abajo |

## Pendiente

### En la app

- **iOS sin probar.** Nunca se compiló ni se ejecutó en iOS. Están declarados los permisos de
  ubicación y el modo de fondo, pero el permiso de notificaciones solo se pide en Android.
- **Cancelaciones en la agenda: camino de respaldo sin verificar en el dispositivo.** Si el canal en
  tiempo real no está disponible, se detectan por el refresco de la agenda (cada 30 s) más una
  consulta a `/live`. Solo lo cubren los tests; en el emulador se probó el camino en tiempo real.
- **Resumen del viaje.** Dice "Sin incidentes" aunque haya habido un SOS, porque solo lista incidentes.
  Hay que decidir si el SOS debe aparecer ahí.
- **Aviso de SOS resuelto.** El snackbar tapa unos 4 s los botones de Incidente y SOS.
- **Mapa.**
  - Las teselas salen del servidor público de OpenStreetMap, que solo es apto para desarrollo
    ([política de uso](https://operations.osmfoundation.org/policies/tiles)). Para producción hace falta
    un proveedor de teselas.
  - Se vio un mapa gris en una prueba y no se pudo reproducir ni demostrar la causa. Los fallos de
    teselas ahora se registran en debug.
  - La línea entre paradas es recta: no sigue las calles.
- **Viaje de retorno.** El flujo de subida y bajada del retorno no se probó contra el backend real.
- **Cola offline.** No se vacía al cerrar sesión voluntariamente (se guarda por viaje).
- **Iniciar y finalizar un viaje exigen conexión** (iniciar, por contrato; finalizar, porque no se cierra con
  registros sin enviar). El abordaje, los incidentes y el SOS sí se guardan sin señal y se envían al volver.
- **Incidente.** Foto y nota de voz figuran como "próximamente"; el backend aún no las admite.
- **Dependencia fijada.** `permission_handler` está en `^12.0.1`: la versión 13 exige Android SDK 37 y
  Gradle falla con `Failed to find target with hash string 'android-37'`. No subirla hasta resolverlo.

### Depende del backend (`rutasegura-backend`)

- **Notification no funciona.** La bandeja, los comunicados y las entregas fallidas responden 503
  `NOTIFICATION_DEPENDENCY_UNAVAILABLE`, porque el monolito no expone cuatro endpoints internos
  (`/internal/v1/notifications/recipients/{operators,students,announcement}` y `.../student-links`).
  Ver §13.1 del README del backend.
- **El conductor no es destinatario de Notification.** Los avisos van a tutores y administradores. Si se
  quiere que el conductor reciba comunicados o avisos con la app cerrada, hay que definirlo en el backend.
- **Push (FCM).** No existe en la app, que tampoco registra suscripciones en
  `PUT /push-subscriptions/{installationId}`. En el backend es opcional por entorno; no se verificó si está
  configurado.
- **SOS resuelto.** El canal en tiempo real no emite nada al resolverse un SOS; la app lo detecta con
  `hasActiveSos` de `/live`.
- **"Llamar a la empresa" en el SOS.** Falta un campo de teléfono en el endpoint de organización (y
  `url_launcher` en la app).
- **Cancelar viajes.** El backend solo lo permite antes de iniciarlo, por eso un conductor ya en
  camino nunca recibe una cancelación.

### Antes de publicar

- Reemplazar el identificador de aplicación de ejemplo `com.example.rutasegura` y configurar la firma
  de release en Android e iOS.
- Servir el Gateway por HTTPS (el HTTP sin TLS solo está permitido en desarrollo).
