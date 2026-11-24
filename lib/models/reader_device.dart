class ReaderDevice {
  const ReaderDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  ReaderDevice copyWith({String? id, String? name, int? rssi}) {
    return ReaderDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
    );
  }

  factory ReaderDevice.fromMap(Map<Object?, Object?> map) {
    return ReaderDevice(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? 'Lector'}',
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'rssi': rssi};
}
