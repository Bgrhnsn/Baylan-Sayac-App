import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';

/// GÜNCELLEME: Bu ekran artık hem yeni sayaç okuması eklemek hem de
/// mevcut olanı düzenlemek için kullanılıyor.
class NewReadingScreen extends StatefulWidget {
  // HATA ÇÖZÜMÜ: Düzenlenecek kaydı alabilmesi için bu constructor parametresi eklendi.
  final MeterReading? readingToEdit;

  const NewReadingScreen({super.key, this.readingToEdit});

  @override
  State<NewReadingScreen> createState() => _NewReadingScreenState();
}

class _NewReadingScreenState extends State<NewReadingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _installationIdCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _locationTextCtrl = TextEditingController();
  final _invoiceAmountCtrl = TextEditingController();

  DateTime _pickedTime = DateTime.now();
  DateTime? _pickedDueDate;
  Set<String> _selectedUnit = {'kWh'};
  Position? _gpsPos;
  bool _isGettingLocation = false;
  bool _isSaving = false;

  // Bu ekranın düzenleme modunda olup olmadığını belirten bir getter.
  bool get isEditMode => widget.readingToEdit != null;

  @override
  void initState() {
    super.initState();
    // Eğer düzenleme modundaysak, form alanlarını mevcut verilerle doldur.
    if (isEditMode) {
      final reading = widget.readingToEdit!;
      _installationIdCtrl.text = reading.installationId;
      _valueCtrl.text = reading.readingValue.toString();
      _locationTextCtrl.text = reading.locationText ?? '';
      _invoiceAmountCtrl.text = reading.invoiceAmount?.toString() ?? '';
      _pickedTime = reading.readingTime;
      _pickedDueDate = reading.dueDate;
      _selectedUnit = {reading.unit ?? 'kWh'};
      if (reading.gpsLat != null && reading.gpsLng != null) {
        _gpsPos = Position(latitude: reading.gpsLat!, longitude: reading.gpsLng!, timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
      }
    }
  }

  @override
  void dispose() {
    _installationIdCtrl.dispose();
    _valueCtrl.dispose();
    _locationTextCtrl.dispose();
    _invoiceAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLocationPermission() async {
    // Bu fonksiyon doğru çalıştığı için bir değişiklik yapılmadı.
    setState(() {
      _isGettingLocation = true;
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Konum servisleri kapalı. Lütfen açın.')));
      }
      setState(() => _isGettingLocation = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Konum izni verilmedi.')));
        }
        setState(() => _isGettingLocation = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Konum izni kalıcı olarak reddedildi. Ayarlardan izin vermeniz gerekiyor.')));
      }
      setState(() => _isGettingLocation = false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium
      );

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        String address = 'Adres bulunamadı.';
        if (placemarks.isNotEmpty) {
          final Placemark place = placemarks.first;
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.postalCode,
            place.country
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }

        setState(() {
          _gpsPos = position;
          _locationTextCtrl.text = address;
        });

      } catch (e) {
        setState(() {
          _gpsPos = position;
          _locationTextCtrl.text = 'Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}';
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum alınamadı: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  /// KAYDETME/GÜNCELLEME FONKSİYONU
  Future<void> _saveOrUpdate() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Giriş yapmalısınız.');

      final readingValue = double.tryParse(_valueCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
      final invoiceAmount = double.tryParse(_invoiceAmountCtrl.text.trim().replaceAll(',', '.'));

      // HATA ÇÖZÜMÜ: MeterReading nesnesi oluşturmak yerine,
      // doğrudan Firestore'a gönderilecek bir Map oluşturuyoruz.
      // Bu, yeni kayıt eklerken 'id' hatasını önler.
      final data = {
        'installationId': _installationIdCtrl.text.trim(),
        'readingValue': readingValue,
        'readingTime': _pickedTime,
        'unit': _selectedUnit.first,
        'locationText': _locationTextCtrl.text.trim().isEmpty ? null : _locationTextCtrl.text.trim(),
        'gpsLat': _gpsPos?.latitude,
        'gpsLng': _gpsPos?.longitude,
        'invoiceAmount': invoiceAmount,
        'dueDate': _pickedDueDate,
        'dueAmount': null,
      };

      final userReadings = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('readings');
      String message;

      if (isEditMode) {
        await userReadings.doc(widget.readingToEdit!.id).update(data);
        message = 'Kayıt başarıyla güncellendi.';
      } else {
        await userReadings.add(data);
        message = 'Sayaç okuması başarıyla kaydedildi.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bir hata oluştu: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditMode ? 'Okumayı Düzenle' : 'Yeni Sayaç Okuma')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _installationIdCtrl, decoration: const InputDecoration(labelText: 'Tesisat Numarası', prefixIcon: Icon(Icons.confirmation_number_outlined), border: OutlineInputBorder()), validator: (v) => v!.trim().isEmpty ? 'Tesisat numarası zorunludur' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _valueCtrl, decoration: const InputDecoration(labelText: 'Okuma Değeri', prefixIcon: Icon(Icons.speed_outlined), border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { if (v == null || v.trim().isEmpty) return 'Okuma değeri girin'; if (double.tryParse(v.trim().replaceAll(',', '.')) == null) return 'Lütfen geçerli bir sayı girin'; return null; }),
              const SizedBox(height: 16),
              SegmentedButton<String>(segments: const [ButtonSegment(value: 'kWh', label: Text('kWh'), icon: Icon(Icons.electric_bolt)), ButtonSegment(value: 'm³', label: Text('m³'), icon: Icon(Icons.water_drop))], selected: _selectedUnit, onSelectionChanged: (newSelection) => setState(() => _selectedUnit = newSelection)),
              const SizedBox(height: 16),
              ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)), leading: const Icon(Icons.today), title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Okuma Zamanı', style: Theme.of(context).textTheme.bodySmall), Text(DateFormat('dd MMMM HH:mm', 'tr_TR').format(_pickedTime), style: Theme.of(context).textTheme.titleMedium)]), trailing: const Icon(Icons.edit_calendar), onTap: () async { final d = await showDatePicker(context: context, initialDate: _pickedTime, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), locale: const Locale('tr', 'TR')); if (d == null || !mounted) return; final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_pickedTime)); if (t == null) return; setState(() => _pickedTime = DateTime(d.year, d.month, d.day, t.hour, t.minute)); }),
              const SizedBox(height: 16),
              TextFormField(controller: _locationTextCtrl, decoration: InputDecoration(labelText: 'Adres / Lokasyon Açıklaması', border: const OutlineInputBorder(), prefixIcon: _isGettingLocation ? const Padding(padding: EdgeInsets.all(10.0), child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(icon: const Icon(Icons.my_location), tooltip: 'GPS ile Doldur', onPressed: _handleLocationPermission))),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 10),
              Text('Fatura Bilgileri (Opsiyonel)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(controller: _invoiceAmountCtrl, decoration: const InputDecoration(labelText: 'Fatura Tutarı', prefixIcon: Icon(Icons.receipt_long_outlined), border: OutlineInputBorder(), suffixText: 'TL'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)), leading: const Icon(Icons.event_busy), title: Text(_pickedDueDate == null ? 'Son Ödeme Tarihi Seçin' : DateFormat('dd MMMM yyyy', 'tr_TR').format(_pickedDueDate!)), trailing: _pickedDueDate == null ? const Icon(Icons.calendar_month) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _pickedDueDate = null)), onTap: () async { final d = await showDatePicker(context: context, initialDate: _pickedDueDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), locale: const Locale('tr', 'TR')); if (d == null) return; setState(() => _pickedDueDate = d); }),
              const SizedBox(height: 24),
              ElevatedButton.icon(style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: _isSaving ? Colors.grey : Theme.of(context).primaryColor, foregroundColor: Colors.white), onPressed: _isSaving ? null : _saveOrUpdate, icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(isEditMode ? Icons.check : Icons.save), label: Text(isEditMode ? 'Güncelle' : 'Kaydet')),
            ],
          ),
        ),
      ),
    );
  }
}
