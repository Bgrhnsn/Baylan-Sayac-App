// models/meter_reading.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MeterReading {
  final String id;
  // YENİ: Kullanıcının sayaca verdiği özel isim
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
      'meterName': meterName, // GÜNCELLEME: Firestore'a gönderilecek veriye eklendi.
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
    // doc.data() null olabilir, bu yüzden güvenli bir şekilde erişelim
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return MeterReading(
      id: doc.id,
      meterName: data['meterName'],
      installationId: data['installationId'] ?? '', // Null kontrolü
      readingValue: (data['readingValue'] as num?)?.toDouble() ?? 0.0, // null check
      readingTime: (data['readingTime'] as Timestamp?)?.toDate() ?? DateTime.now(), // null check
      unit: data['unit'],
      locationText: data['locationText'],
      gpsLat: (data['gpsLat'] as num?)?.toDouble(),
      gpsLng: (data['gpsLng'] as num?)?.toDouble(),
      invoiceAmount: (data['invoiceAmount'] as num?)?.toDouble(),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      invoiceImageUrl: data['invoiceImageUrl'], // fatura görseli değişkeni
    );
  }
}