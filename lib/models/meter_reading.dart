import 'package:cloud_firestore/cloud_firestore.dart';

class MeterReading {
  final String id;
  final String? meterName;
  final String installationId;
  final double readingValue;
  final DateTime readingTime;
  final String? unit;
  final String? locationText;
  final double? gpsLat;
  final double? gpsLng;
  final double? invoiceAmount;
  final DateTime? dueDate;
  final double? dueAmount;
  final String? invoiceImageUrl;

  MeterReading({
    required this.id,
    this.meterName,
    required this.installationId,
    required this.readingValue,
    required this.readingTime,
    this.unit,
    this.locationText,
    this.gpsLat,
    this.gpsLng,
    this.invoiceAmount,
    this.dueDate,
    this.dueAmount,
    this.invoiceImageUrl,
  });

  /// Bu metod, nesneyi Firestore'a yazmak için bir Map'e dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'meterName': meterName,
      'installationId': installationId,
      'readingValue': readingValue,
      'readingTime': readingTime,
      'unit': unit,
      'locationText': locationText,
      'gpsLat': gpsLat,
      'gpsLng': gpsLng,
      'invoiceAmount': invoiceAmount,
      'dueDate': dueDate,
      'dueAmount': dueAmount,
    };
  }

  /// Bu factory constructor, Firestore'dan gelen bir dokümanı
  /// MeterReading nesnesine dönüştürür.
  factory MeterReading.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // HATA ÇÖZÜMÜ: Veritabanından gelen tarih verisini güvenli bir şekilde
    // okumak için bir yardımcı fonksiyon oluşturuldu.
    DateTime? _safeParseTimestamp(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      // Eğer veri hatalı bir şekilde String olarak kaydedilmişse,
      // çökmek yerine null döndürerek hatayı engeller.
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return null;
        }
      }
      return null;
    }

    return MeterReading(
      id: doc.id,
      meterName: data['meterName'],
      installationId: data['installationId'] ?? '',
      readingValue: (data['readingValue'] as num?)?.toDouble() ?? 0.0,
      // Okuma zamanı için de güvenli okuma kullanılıyor.
      readingTime: _safeParseTimestamp(data['readingTime']) ?? DateTime.now(),
      unit: data['unit'],
      locationText: data['locationText'],
      gpsLat: (data['gpsLat'] as num?)?.toDouble(),
      gpsLng: (data['gpsLng'] as num?)?.toDouble(),
      invoiceAmount: (data['invoiceAmount'] as num?)?.toDouble(),
      // Son ödeme tarihi için güvenli okuma kullanılıyor.
      dueDate: _safeParseTimestamp(data['dueDate']),
      invoiceImageUrl: data['invoiceImageUrl'],
    );
  }
}
