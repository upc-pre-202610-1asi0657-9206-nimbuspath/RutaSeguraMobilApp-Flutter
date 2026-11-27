# Avisos del conductor en Android

La campana de Inicio/Perfil abre la bandeja autenticada con cinco tipos de aviso:

| Aviso | Qué debe revisar el conductor |
| --- | --- |
| Viaje asignado | Agenda y horario |
| Viaje cancelado | Estado antes de salir |
| Inasistencia avisada por la familia | Pasajeros del viaje |
| SOS atendido por la empresa | Estado cuando esté detenido |
| Comunicado de la empresa | Mensaje autorizado |

No se generan push para repetir las propias marcaciones del conductor. El backend sólo permite cancelar antes de iniciar un viaje.

## Configuración y APK

Se incorporó `android/app/google-services.json`, configuración pública de `rutasegura-f2703` para `com.example.rutasegura`. La clave privada de Firebase Admin permanece en AWS. Si cambia el applicationId, registrar ese paquete en Firebase y descargar su configuración correspondiente. Se necesitan Google Play Services y permiso de notificaciones en Android.

Requisitos: Flutter compatible con Dart `^3.13.5`, Android SDK 37 y JDK compatible con el Gradle del proyecto. La verificación usó Flutter 3.50.1 / Dart 3.14.0 instalado en `E:\codex-tooling\flutter`, fuera del repositorio. No cambió el requisito Dart.

```powershell
cd E:\RutaSeguraMobilApp-Flutter
.\scripts\Build-TestApk.ps1 `
  -GatewayUrl http://ec2-3-216-48-246.compute-1.amazonaws.com `
  -FlutterExecutable E:\codex-tooling\flutter\bin\flutter.bat
```

Con Flutter en PATH se puede omitir `-FlutterExecutable`. El script detiene Gradle, limpia artefactos y guarda Pub en `.local/pub-cache` en la unidad del proyecto; resuelve los errores de Kotlin `different roots`/cachés registradas sin cambiar variables globales. Android SDK y JDK se detectan desde la configuración local o sus variables del entorno.

APK: `build/app/outputs/flutter-apk/app-debug.apk`. Es debug, con firma de prueba y la configuración HTTP de desarrollo existente. Publicar requiere Gateway HTTPS, applicationId definitivo y firma release.

## Prueba conjunta pendiente

1. Desplegar **Monolith, Trip & Tracking y Notifications** con los cambios del backend. Reutilizar el secreto Firebase existente en AWS. No hay una migración nueva de Notifications.
2. Instalar el APK, entrar como DRIVER con perfil verificado y activar **Avisos push en este celular** desde la campana. Aceptar permiso y comprobar registro correcto.
3. Como ADMIN, programar un nuevo viaje para ese conductor, cancelar otro viaje pendiente y publicar un comunicado. Como PARENT vinculado, avisar una inasistencia. Levantar un SOS desde el viaje y resolverlo como ADMIN.
4. Repetir con la app abierta y en segundo plano. Tocar el aviso abre la bandeja autenticada y marca el detalle como leído. Consultar agenda no ejecuta acciones del viaje.
5. Comprobar permisos denegados/revocados, reconexión, token renovado, cierre/cambio de cuenta y suspensión del conductor. Otros usuarios/empresas no deben recibir ni consultar estos avisos. Una ausencia marcada por el conductor no genera otro push.

La recepción en Android contra AWS permanece pendiente. La aceptación del proveedor no acredita visualización. Android puede suprimir avisos si se fuerza la detención de la app o se restringen permisos/batería.

## Comportamiento

- Bandeja persistente en Notifications/MySQL, paginada con cursor y deduplicada por id. No se cachean mensajes privados en SharedPreferences. Se descartan respuestas de una sesión anterior.
- SignalR `/hubs/notifications` transmite pistas. REST recupera contenido autorizado al reconectar, al reanudar y cada 30 segundos en primer plano. El hub se cierra al pasar a segundo plano o salir, sin cambiar el servicio GPS ni el hub de Tracking.
- FCM contiene sólo `notificationId` y texto genérico. En primer plano se muestra un aviso local; en segundo plano Android muestra FCM. El handler de background no vuelve a mostrarlo. Se usa canal `rutasegura_updates`, importancia normal, icono propio y tag estable por aviso.
- Los avisos no tienen botones operativos ni muestran nombres, GPS o contenido libre en la pantalla bloqueada. El detalle se consulta cuando el conductor esté detenido.
- Al salir se intenta la baja remota antes de quitar el JWT, se desactiva auto-init de FCM y se elimina el token. La revocación pendiente se reintenta al reconectar; un token con eliminación pendiente no se reutiliza con otra cuenta. Offline la baja remota puede demorarse. Sólo se retiran avisos del canal de Notifications, conservando el aviso del servicio GPS.
- La idempotencia del backend garantiza un aviso lógico por evento/destinatario. No se promete exactamente una entrega física ante todos los fallos y reinicios del proveedor.
- Esta integración push habilita Android. iOS necesita su aplicación Firebase, `GoogleService-Info.plist`, capacidades push/APNs y verificación propia. La bandeja REST es independiente de FCM.

## Verificación local

146 pruebas Flutter aprobadas, incluidas 10 de Notifications: permisos, rotación, baja online/offline, paginación, aislamiento de sesión, enlaces y render a 390 px. Análisis sin errores ni warnings usando `flutter analyze --no-fatal-infos`; permanecen avisos informativos de APIs/deprecaciones con el SDK nuevo. APK debug compilado contra el Gateway AWS. Falta aceptación en un celular después del despliegue backend.

Referencia: [recepción de mensajes Flutter/FCM](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
