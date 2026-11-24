import 'package:pigeon/pigeon.dart';

// This file is where you define the interface between Dart code and host
// platform code. After editing this file, run
//   dart run pigeon --input pigeon/messages.dart
// to re-generate all of the output files.
//
// If you add new platforms to your plugin, add the corresponding output
// options in the PigeonOptions below.
//
// To learn more about Pigeon, see https://pub.dev/packages/pigeon.

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'cubip_rfid',
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/megadeep/cubip_rfid/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.megadeep.cubip_rfid'),
    swiftOut: [
      'ios/cubip_rfid/Sources/cubip_rfid/Messages.g.swift',
    ],
  ),
)
@HostApi()
abstract class CubipRfidPluginApi {
  /// Returns the system version of the host platform.
  String getPlatformVersion();
}
