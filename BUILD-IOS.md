# Compilar Cubip Scan en iOS

El lado iOS del plugin ya está configurado (`packages/cubip_rfid`), pero **no se puede compilar en Linux**. Hace falta un Mac con **Xcode 16** (o posterior) y un iPhone físico.

## Por qué no sirve el simulador

`GReader.framework` (SDK A7, Swift 6, iOS 12+) solo incluye la arquitectura **arm64 de dispositivo**. No trae slice para simulador (`x86_64` ni `arm64-simulator`). El `podspec` excluye el simulador a propósito. Hay que firmar y correr la app en un iPhone.

## Pasos

1. Instala Flutter 3.50 (u otra 3.50.x estable) y Xcode 16. Acepta la licencia de Xcode:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   sudo xcodebuild -license accept
   flutter doctor
   ```
2. Copia este directorio `cubip-scan/` al Mac.
3. En la raíz del proyecto:
   ```bash
   flutter pub get
   cd ios
   pod install
   cd ..
   ```
4. Abre `ios/Runner.xcworkspace` en Xcode 16 (no el `.xcodeproj`).
5. El identificador por defecto es `com.megadeep.cubipscan`. Si tu equipo de desarrollo usa otro, cámbialo en *Signing & Capabilities* (`PRODUCT_BUNDLE_IDENTIFIER`) y, si aplica, en Android con `-PCUBIP_APPLICATION_ID=...`.
6. Elige un **iPhone físico**, no un simulador. En *Signing*, selecciona tu equipo y deja que Xcode gestione el perfil.
7. La app ya declara:
   - `NSBluetoothAlwaysUsageDescription`
   - `NSBluetoothPeripheralUsageDescription`
8. Compila e instala:
   ```bash
   flutter build ios --debug
   flutter run -d <id-del-iphone>
   ```
   o pulsa Run en Xcode.

## Si `pod install` no encuentra GReader

El framework vive en `packages/cubip_rfid/ios/Frameworks/GReader.framework` y el plugin lo declara como `vendored_frameworks`. Si CocoaPods no lo copia, comprueba que esa carpeta exista y vuelve a ejecutar `pod install --repo-update`.

## Swift

El plugin está en Swift y enlaza `GReader` (compilado con Swift 6). Xcode 16 incluye esa herramienta. El `podspec` usa `swift_version = 5.0` para el código del plugin, que es compatible.

## Prueba en dispositivo

1. Activa el Bluetooth y acepta el permiso de la app.
2. En **Conectar**, escanea y elige el GEE-UR-A7 (verás el RSSI).
3. En **Lectura**, inicia el inventario. El bot nativo del lector no interviene: esta app habla con el SDK.
4. En **Ajustes**, aplica la banda Colombia si no se aplicó al conectar.

Sin un iPhone y el lector físico, esta parte queda sin verificar.


## Login OIDC

La app usa `flutter_appauth` con el cliente público `wms-mobile` y el redirect `com.megadeep.cubipscan:/oauth`. `Info.plist` ya declara el esquema `com.megadeep.cubipscan` en `CFBundleURLTypes`. En Keycloak hay que registrar esa URI de redirección.

El servidor se configura en **Ajustes › Avanzado**: URL de la API, URL de Keycloak, realm e issuer (se arma como `{keycloak}/realms/{realm}` y se puede sobrescribir). El botón «Probar conexión» consulta `/.well-known/openid-configuration`, comprueba que el issuer coincida y hace `GET {api}/healthz` (debe responder 200).

«Probar conexión» consulta `GET {api}/healthz` y espera un 200.

## Flavors (demo y cliente)

En Android hay dos product flavors en la dimensión `env`: `demo` y `cliente`, con el mismo `applicationId` (`com.megadeep.cubipscan`, sin sufijo). La build de Dart usa `--flavor` (Flutter define `appFlavor`) y, de forma explícita, `--dart-define=APP_FLAVOR=demo|cliente`. En `demo`, http solo se acepta en la LAN. En `cliente`, se rechaza todo http, incluso en la LAN.

Para replicarlo en iOS:

1. Crea dos schemes (o configuraciones xcconfig), por ejemplo `demo` y `cliente`, y lanza con `flutter run --flavor demo --dart-define=APP_FLAVOR=demo` o el equivalente de `cliente`.
2. En el scheme/xcconfig **demo**, deja `NSAllowsLocalNetworking` y `NSLocalNetworkUsageDescription` como están en el `Info.plist` actual, para el piloto en la LAN.
3. En el scheme **cliente**, quita `NSAllowsLocalNetworking` (o ponlo en `false`) en el Info.plist de esa configuración, para que ATS no permita http. El validador de la app también rechaza cualquier http en este flavor.
4. No hace falta cambiar el `CFBundleIdentifier` ni el redirect de OIDC si se mantiene el mismo applicationId.

`flutter_appauth` activa `allowInsecureConnections` únicamente cuando el issuer es http de LAN y el flavor es `demo`.
