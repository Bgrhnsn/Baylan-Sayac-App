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

  MeterReading({
    required this.id,
    this.meterName, // GÜNCELLEME: Constructor'a eklendi.
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
  factory MeterReading.fromSnapshot(DocumentSnapshot snap) {
    var data = snap.data() as Map<String, dynamic>;

    return MeterReading(
      id: snap.id,
      meterName: data['meterName'], // GÜNCELLEME: Firestore'dan veri okunurken eklendi.
      installationId: data['installationId'],
      readingValue: data['readingValue'],
      readingTime: (data['readingTime'] as Timestamp).toDate(),
      unit: data['unit'],
      locationText: data['locationText'],
      gpsLat: data['gpsLat'],
      gpsLng: data['gpsLng'],
      invoiceAmount: data['invoiceAmount'],
      dueDate: data['dueDate'] != null ? (data['dueDate'] as Timestamp).toDate() : null,
      dueAmount: data['dueAmount'],
    );
  }
}
