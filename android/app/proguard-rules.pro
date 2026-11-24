# SDK Java del lector Geenfc (reader.jar) y serial/BLE auxiliares.
-keep class com.gg.reader.** { *; }
-keepclassmembers class com.gg.reader.** { *; }
-keep class com.gg.** { *; }
-keep class com.android.usbserial.** { *; }
-keep class com.hoho.android.usbserial.** { *; }
-dontwarn com.gg.reader.**
-dontwarn com.gg.**
-dontwarn com.android.usbserial.**
-dontwarn com.hoho.android.usbserial.**

# Plugin nativo Cubip RFID y la app.
-keep class com.megadeep.cubip_rfid.** { *; }
-keep class com.megadeep.cubip_scan.** { *; }
-keep class com.megadeep.cubipscan.** { *; }

# JNI / .so del SDK.
-keepclasseswithmembernames class * {
    native <methods>;
}

# flutter_appauth / AppAuth
-keep class net.openid.appauth.** { *; }
-dontwarn net.openid.appauth.**
