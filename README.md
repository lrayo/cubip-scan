# Cubip Scan

App Flutter (Android e iOS) para el lector portátil UHF RFID **Geenfc GEE-UR-A7**, con la marca Cubip y la interfaz en español.

Identificador por defecto: `com.megadeep.cubipscan` (se puede cambiar con la propiedad de Gradle `CUBIP_APPLICATION_ID` o editando `PRODUCT_BUNDLE_IDENTIFIER` en Xcode).

## Qué incluye este MVP

- Conexión por Bluetooth al lector GEE-UR-A7.
- Inventario continuo, lista de etiquetas sin duplicados, conteo y última señal.
- Ajuste de potencia y banda Colombia (915–928 MHz).
- Inicio de sesión OIDC (PKCE) y selección de bodega.
- Envío de lecturas al WMS (`POST /api/v1/rfid/read-batches`) con cola offline, reintentos y `client_read_id` para no duplicar envíos.
- Contrato OpenAPI en `contracts/rfid-reads.openapi.yaml` (borrador 0.3.0-draft): lotes RFID, directorio de ubicaciones y `/healthz`.
- Modo demo, para presentar la app sin el lector físico.
- Exportación de lecturas a CSV.

## Requisitos

- Flutter 3.50 (en esta caja: `/home/box/flutter`)
- Android SDK (en esta caja: `/home/box/android-sdk`)
- JDK 17 o 21
- Para iOS: un Mac con Xcode 16. Ver [BUILD-IOS.md](BUILD-IOS.md).

## Compilar el APK de depuración (arm64)

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/home/box/android-sdk
export PATH="/home/box/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"
cd /workspace/cubip-scan
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --flavor demo --dart-define=APP_FLAVOR=demo --target-platform android-arm64
```

El APK de depuración (flavor `demo`) queda en `build/app/outputs/flutter-apk/`.

## Compilar el APK de entrega (release, arm64)

```bash
flutter build apk --release --flavor demo --dart-define=APP_FLAVOR=demo --split-per-abi --target-platform android-arm64
flutter build apk --release --flavor cliente --dart-define=APP_FLAVOR=cliente --split-per-abi --target-platform android-arm64
```

Los APK quedan en `build/app/outputs/flutter-apk/app-demo-arm64-v8a-release.apk` y `app-cliente-arm64-v8a-release.apk`. Esta compilación usa R8/minify y se firma con la clave de depuración si no hay un keystore de cliente. Para el APK final del cliente hace falta un keystore propio. Ambos flavors comparten el `applicationId` `com.megadeep.cubipscan` (sin sufijo). En `demo`, http solo se acepta en la LAN; en `cliente`, se rechaza todo http.

## Pruebas

- `flutter test` cubre parseo de lecturas, deduplicación, tablas de frecuencia y estado.
- `flutter test --update-goldens` regenera las capturas de `test/goldens/` (también se copian a `screenshots/`).

## Aviso

No se ejecutaron los binarios del SDK del fabricante (`.exe`, `.apk`, `.dll`). El inventario real contra un GEE-UR-A7 queda pendiente de prueba con el lector físico.
