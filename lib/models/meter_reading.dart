// models/meter_reading.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MeterReading {
  // GÜNCELLEME: Doküman ID'sini saklamak için alan eklendi.
  final String id;

  MeterReading({
    required this.id, // GÜNCELLEME: Constructor'a eklendi.
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

  /// Benzersiz sayaç/tesisat numarası
  final String installationId;

  /// Okuma değeri (m³ veya kWh)
  final double readingValue;

  /// Okuma zamanı (otomatik + değiştirilebilir)
  final DateTime readingTime;

  /// Ölçüm birimi (isteğe bağlı, arayüzden alınır)
  final String? unit; // örnek: "kWh", "m³"

  /// Kullanıcı girişi lokasyon açıklaması (isteğe bağlı)
  final String? locationText;

  /// GPS koordinatları (isteğe bağlı)
  final double? gpsLat;
  final double? gpsLng;

  /// Fatura tutarı (TL)
  final double? invoiceAmount;

  /// Son ödeme tarihi (isteğe bağlı)
  final DateTime? dueDate;

  /// Son ödeme tutarı (güncel borç gibi)
  final double? dueAmount;

  /// Bu metod, nesneyi Firestore'a yazmak için bir Map'e dönüştürür.
  Map<String, dynamic> toJson() {
    return {
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

  /// GÜNCELLEME: Bu factory constructor artık doküman ID'sini de alıyor.
  /// Firestore'dan gelen bir dokümanı MeterReading nesnesine dönüştürür.
  factory MeterReading.fromSnapshot(DocumentSnapshot snap) {
    var data = snap.data() as Map<String, dynamic>;

    return MeterReading(
      id: snap.id, // Doküman ID'si alınıyor.
      installationId: data['installationId'],
      readingValue: data['readingValue'],
      // Firestore'dan gelen Timestamp'i DateTime'a çeviriyoruz.
      readingTime: (data['readingTime'] as Timestamp).toDate(),
      unit: data['unit'],
      locationText: data['locationText'],
      gpsLat: data['gpsLat'],
      gpsLng: data['gpsLng'],
      invoiceAmount: data['invoiceAmount'],
      // dueDate null olabilir, bu yüzden kontrol ediyoruz.
      dueDate: data['dueDate'] != null ? (data['dueDate'] as Timestamp).toDate() : null,
      dueAmount: data['dueAmount'],
    );
  }
}
