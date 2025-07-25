// lib/new_reading_screen.dart
// ===========================================================
// FINAL CONSOLIDATED VERSION  v5.8  (2025‑07‑23)
// -----------------------------------------------------------
//  🔄  Ana iyileştirmeler
//  • Debug Modu: AppBar menüsüne, son OCR taramasının ham metnini
//    gösteren bir debug seçeneği eklendi.
//  • _lastOcrResultText: Son tarama sonucunu saklamak için state eklendi.
// ===========================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // YENİ: Clipboard için eklendi.
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';

// ———————————————————————————————————————————  Helpers
class _Candidate {
  _Candidate({required this.value, required this.boundingBox, this.score = 0});
  final String value;
  final Rect boundingBox;
  double score;
}
class _LineInfo {
  _LineInfo(this.text, this.normalizedText, this.boundingBox);
  final String text;
  final String normalizedText;
  final Rect boundingBox;
}

double _toDouble(String s) =>
    double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

// ———————————————————————————————————————————  Widget
class NewReadingScreen extends StatefulWidget {
  const NewReadingScreen({super.key, this.readingToEdit});
  final MeterReading? readingToEdit;
  @override
  State<NewReadingScreen> createState() => _NewReadingScreenState();
}

class _NewReadingScreenState extends State<NewReadingScreen> {
  // controllers
  final _formKey = GlobalKey<FormState>();
  final _meterNameCtrl = TextEditingController();
  final _installationIdCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _locationTextCtrl = TextEditingController();
  final _invoiceAmountCtrl = TextEditingController();

  // state
  DateTime _pickedTime = DateTime.now();
  DateTime? _pickedDueDate;
  Set<String> _selectedUnit = {'kWh'};
  Position? _gpsPos;
  bool _isGettingLocation = false;
  bool _isSaving = false;
  bool _isScanning = false;
  bool get _isEdit => widget.readingToEdit != null;
  String? _lastOcrResultText; // YENİ: Son OCR sonucunu saklamak için.

  // ---------------------------------------------------- lifecycle
  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final r = widget.readingToEdit!;
      _meterNameCtrl.text = r.meterName ?? '';
      _installationIdCtrl.text = r.installationId;
      _valueCtrl.text = r.readingValue.toString();
      _locationTextCtrl.text = r.locationText ?? '';
      _invoiceAmountCtrl.text = r.invoiceAmount?.toString() ?? '';
      _pickedTime = r.readingTime;
      _pickedDueDate = r.dueDate;
      _selectedUnit = {r.unit ?? 'kWh'};
      if (r.gpsLat != null && r.gpsLng != null) {
        _gpsPos = Position(
          latitude: r.gpsLat!,
          longitude: r.gpsLng!,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      }
    }
  }

  @override
  void dispose() {
    _meterNameCtrl.dispose();
    _installationIdCtrl.dispose();
    _valueCtrl.dispose();
    _locationTextCtrl.dispose();
    _invoiceAmountCtrl.dispose();
    super.dispose();
  }

  // ————————————————————————————————  OCR FLOW
  Future<void> _scanWithOcr() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.filter,
        pageLimit: 1,
        isGalleryImport: true,
      ),
    );

    setState(() => _isScanning = true);
    try {
      final result = await scanner.scanDocument();
      await scanner.close();
      if (result.images.isEmpty) return;

      final imgFile = File(result.images.first);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recText = await recognizer.processImage(InputImage.fromFile(imgFile));
      await recognizer.close();

      // YENİ: OCR sonucunu state'e kaydet.
      if (mounted) {
        setState(() {
          _lastOcrResultText = recText.text;
        });
      }

      final data = _parse(recText);
      _populateFields(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data.isEmpty
              ? 'Faturadan otomatik bilgi alınamadı.'
              : '${data.length} alan dolduruldu: ${data.keys.join(', ')}'),
          backgroundColor: data.isEmpty ? Colors.orange : Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('OCR hatası: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ————————————————————————————————  Normalization
  String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u')
      .replaceAll(RegExp(r'[^a-z0-9%./:\-\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();



  // ————————————————————————————————  ADVANCED PARSER
  // Lütfen bu fonksiyonun tamamını kopyalayıp mevcut olanla değiştirin.
  // Lütfen _parse fonksiyonunun TAMAMINI bu nihai sürümle değiştirin.
  Map<String, String> _parse(RecognizedText rec) {
    final elements = rec.blocks
        .expand((b) => b.lines
        .expand((l) => l.elements.map((e) => _LineInfo(e.text, _norm(e.text), e.boundingBox))))
        .toList();

    // =================================================================
    // ADIM 1: FATURA PROFİLLERİNİ (ŞABLONLARINI) TANIMLAMA
    // =================================================================

    // PROFİL 1: İZSU SU FATURASI KURALLARI
    final izsuSpecs = {
      'installationId': {
        'strategies': ['findRight', 'findBelow'],
        'kw': ['sayaç','sayac','sayaç no','sayac no'],
        're': [RegExp(r'(\b\d{7,14}\b)')],
        'negKw': ['vergi', 'dosya', 'tc kimlik', 'fatura', 'musteri','abone'],
      },
      'invoiceAmount': {
        'strategies': ['findBelow', 'findRight'],
        'kw': ['odenecek toplam tutar'],
        're': [RegExp(r'(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})')],
        'negKw': ['kdv', 'yuvarlama', 'bedel', 'taksit', 'donem tutari', 'ara toplam',
          'izsu fatura toplami', 'toplam', 'su tuketim'],
        'lineFilter': (String raw) => RegExp(r'[.,]\d{2}\b').hasMatch(raw),
      },
      'dueDate': {
        'strategies': ['findRight','findBelow'],
        'kw': ['son odeme tarihi', 's o t','son ödeme tarihi','SON ÖDEME TARİHİ','SON ODEME TARİHİ','SON ODEME TARIHI'],
        're': [RegExp(r'(\d{2}[./-]\d{2}[./-]\d{2,4})')],
        // 'son okuma tarihi' ifadesi net bir şekilde yasaklandı.
        'negKw': ['okuma','OKUMA','ilk'],
      },
      'readingValue': {
        'strategies': ['findRight'],
        // Anahtar kelimemiz net: Sadece "tüketim" kelimesini arıyoruz.
        'kw': ['tuketim'],
        // İZSU'da tüketim her zaman tam sayıdır.
        're': [RegExp(r'^\d+$')],
        // Akıllı motorumuza hangi ifadelerin yasaklı olduğunu söylüyoruz.
        'negKw': [
          // Çok kelimeli ifadeler artık doğru şekilde tanınacak:
          'su bedeli',
          'tüketim gün say',
          'ilk endeks',
          'son endeks',
          'su birim fiyat',
          'atık su birim fiyat',
          'bölge kodu',

          // Parasal ve diğer alakasız tekil kelimeler:
          'bedel',
          'tutar',
          'toplam',
          'kdv',
          'kademe', // '1 Kademe', '2 Kademe' gibi ifadeleri engeller
          'endeks',
          'oran'
        ],
      },
    };

    // PROFİL 2: GEDİZ ELEKTRİK FATURASI KURALLARI
    final gedizSpecs = {
      'installationId': {
        'strategies': ['findBelow'],
        'kw': ['tekil kod/tesisat no','tesisat no', 'tekil kod','tekil','tesisat'],
        're': [RegExp(r'(\b\d{7,14}\b)')],
        'negKw': ['vergi', 'dosya', 'tc kimlik', 'fatura','seri','sozlesme hesap','sozleşme','sözleşme'],
      },
      'invoiceAmount': {
        'strategies': ['findBelow'],
        'kw': ['odenecek tutar', 'toplam fatura tutari','ödenecek tutar','tutar'],
        're': [RegExp(r'(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})')],
        // Burada 'toplam' yasaklı değil, çünkü 'toplam fatura tutari'nda kullanılıyor.
        'negKw': ['kdv', 'yuvarlama', 'bedel', 'taksit', 'donem tutari'],
        'lineFilter': (String raw) => RegExp(r'[.,]\d{2}\b').hasMatch(raw),
      },
      'dueDate': {
        'strategies': ['findBelow'],
        'kw': ['son odeme tarihi', 's o t','son ödeme tarihi','son odeme tarıhı'],
        're': [RegExp(r'(\d{2}[./-]\d{2}[./-]\d{2,4})')],
        'negKw': ['fatura tarihi', 'okuma tarihi', 'ilk okuma', 'son okuma'],
      },
      'readingValue': {
        'strategies': ['findRight'],
        'kw': ['tüketim(kwh)','tüketim', 'enerji tuketim bedeli','tuketim'],
        're': [RegExp(r'\b\d{1,3}(?:\.\d{3})*,\d{3}\b')], // Elektrikte ondalıklı olabilir
        'negKw': ['fiyat', 'oran', 'tl', 'kr', 'krs', 'bedel(tl)', // Parasal ifadeler
        'yüksek kademe', 'yuksek kademe', // Yanlış kademeyi engelle
        'gece', 'gunduz', 'puant', 'tek zaman', // Zaman dilimlerini engelle
        'endeks', 'indeks', 'fark', // Endeks tablosundaki diğer sütunları engelle
        'ortalama', // Ortalama tüketimi engelle
        'sayac no', 'abone no', 'tesisat no', 'fatura no', // Numaraları engelle
        'kwh', 'gun say', 'gün say' ,'ödenecek tutar','tutar','fatura kodu','elektrik faturası','fatura',
          'fatura otalama'// Birimleri ve gün sayısını engelle],
        ],
      },
    };

    // =================================================================
    // ADIM 2: FATURAYI TANI VE DOĞRU PROFİLİ SEÇ
    // =================================================================
    final fullText = _norm(rec.text);
    Map<String, dynamic> specs;

    if (fullText.contains('izsu')) {
      print("İZSU Fatura Profili Seçildi.");
      specs = izsuSpecs;
    } else if (fullText.contains('gediz')) {
      print("Gediz Fatura Profili Seçildi.");
      specs = gedizSpecs;
    } else {
      print("Varsayılan (Gediz) Fatura Profili Seçildi.");
      specs = gedizSpecs; // Veya genel bir varsayılan profil
    }

    // =================================================================
    // ADIM 3: SEÇİLEN PROFİL İLE AYRIŞTIRMA YAP
    // =================================================================
    final out = <String, String>{};

    for (final entry in specs.entries) {
      final key = entry.key;
      final spec = entry.value as Map<String, dynamic>;
      final strategies = spec['strategies'] as List<String>;
      _Candidate? best;

      for (final strat in strategies) {
        final cand = _findCandidate(elements, spec, _getScorer(strat), key);
        if (cand != null && (best == null || cand.score < best.score)) best = cand;
      }
      if (best != null) out[key] = best.value;
    }

    if (out['readingValue'] != null) {
      // ANCHOR: Yakalanan değerdeki tüm boşlukları kaldır ve sonra birimleri temizle.
      out['readingValue'] = out['readingValue']!
          .replaceAll(' ', '') // Önce tüm boşlukları temizle
          .replaceAll(RegExp(r'\s*(kwh|m3|m³)', caseSensitive: false), '')
          .trim();
    }
    return out;
  }




  // Lütfen bu fonksiyonun tamamını projenizdeki mevcut fonksiyonla değiştirin.
  /// Bu, _findCandidate fonksiyonunun nihai ve güncellenmiş versiyonudur.
  /// Çok kelimeli negatif ifadeleri tanıyabilir ve belirsizlik sorunlarını çözer.
  _Candidate? _findCandidate(List<_LineInfo> elements, Map<String, dynamic> spec,
      double Function(Rect, Rect) scorer, String fieldKey) {
    final kw = (spec['kw'] as List<String>).map(_norm).toList();
    final negKw = (spec['negKw'] as List<String>).map(_norm).toList();
    final res = spec['re'] as List<RegExp>;
    final lineFilter = spec['lineFilter'] as bool Function(String)?;

    // POZİTİF etiketleri bul
    final labels = <_Candidate>[];
    for (final phrase in kw) {
      final phraseWords = phrase.split(' ');
      for (int i = 0; i < elements.length; i++) {
        if (elements[i].normalizedText == phraseWords.first) {
          int matchedWords = 1;
          Rect combinedBox = elements[i].boundingBox;
          for (int j = 1;
          j < phraseWords.length && (i + j) < elements.length;
          j++) {
            final nextElement = elements[i + j];
            if (nextElement.normalizedText == phraseWords[j] &&
                (nextElement.boundingBox.left - combinedBox.right).abs() <
                    nextElement.boundingBox.width) {
              matchedWords++;
              combinedBox = combinedBox.expandToInclude(nextElement.boundingBox);
            } else {
              break;
            }
          }
          if (matchedWords > 0) {
            labels.add(_Candidate(
                value: phrase,
                boundingBox: combinedBox,
                score: -matchedWords.toDouble()));
          }
        }
      }
    }

    if (labels.isEmpty) return null;

    // ANCHOR: GELİŞMİŞ NEGATİF FİLTRELEME MOTORU
    // Bu bölüm, 'su tüketim bedeli' gibi çok kelimeli negatif ifadeleri tanır.
    final negKwRects = <Rect>[];
    for (final phrase in negKw) {
      final phraseWords = phrase.split(' ');
      // Eğer tek kelimelik bir negKw ise, tüm eşleşmeleri doğrudan ekle
      if (phraseWords.length == 1) {
        negKwRects.addAll(elements
            .where((el) => el.normalizedText == phrase)
            .map((el) => el.boundingBox));
      }
      // Eğer çok kelimelik bir negKw ise, ifadeyi bul ve kutusunu birleştir
      else {
        for (int i = 0; i < elements.length; i++) {
          if (elements[i].normalizedText == phraseWords.first) {
            int matchedWords = 1;
            Rect combinedBox = elements[i].boundingBox;
            for (int j = 1;
            j < phraseWords.length && (i + j) < elements.length;
            j++) {
              final nextElement = elements[i + j];
              if (nextElement.normalizedText == phraseWords[j] &&
                  (nextElement.boundingBox.left - combinedBox.right).abs() <
                      nextElement.boundingBox.width) {
                matchedWords++;
                combinedBox =
                    combinedBox.expandToInclude(nextElement.boundingBox);
              } else {
                break;
              }
            }
            if (matchedWords == phraseWords.length) {
              negKwRects.add(combinedBox);
            }
          }
        }
      }
    }

    // Değerleri bul
    final vals = <_Candidate>[];
    for (final el in elements) {
      if (lineFilter != null && !lineFilter(el.text)) continue;

      // Gelişmiş Negatif Filtre: Bu değer, bir negatif ifadenin "yasaklı bölgesinde" mi?
      bool isNearNegativeKeyword = negKwRects.any((negRect) {
        final isVerticallyAligned = (el.boundingBox.center.dy > negRect.top &&
            el.boundingBox.center.dy < negRect.bottom);
        final isToTheRight = el.boundingBox.left > negRect.right;
        final isHorizontallyClose =
            (el.boundingBox.left - negRect.right).abs() <
                (el.boundingBox.width * 3);
        return isVerticallyAligned && isToTheRight && isHorizontallyClose;
      });

      if (isNearNegativeKeyword) continue; // Eğer yasaklı bölgedeyse, bu değeri atla.

      // Değeri regex ile doğrula ve sadece eşleşen kısmı al
      for (final r in res) {
        final cleanText = el.text.replaceAll(' ', '');
        final match = r.firstMatch(cleanText);
        if (match != null && match.group(0) != null) {
          vals.add(
              _Candidate(value: match.group(0)!, boundingBox: el.boundingBox));
          break;
        }
      }
    }

    if (vals.isEmpty) return null;

    // Puanlama ve geometrik sıralama
    for (final v in vals) {
      double minD = double.infinity;
      for (final l in labels) {
        final d = scorer(l.boundingBox, v.boundingBox) + (l.score * 10);

        // ANCHOR: HATA AYIKLAMA İÇİN BU BLOK EKLENDİ
        // Sadece 'readingValue' alanını işlerken skorları yazdır
        if (fieldKey == 'readingValue') {
          print(
              '[DEBUG readingValue] Aday: "${v.value}", Çapa: "${l.value}", Skor: ${d.toStringAsFixed(2)}');
        }

        if (d < minD) minD = d;
      }
      v.score = minD;
    }

    vals.removeWhere((v) => v.score == double.infinity);
    if (vals.isEmpty) return null;

    vals.sort((a, b) => a.score.compareTo(b.score));

    // dueDate için özel kronolojik sıralama mantığı
    if (fieldKey == 'dueDate' && vals.isNotEmpty) {
      vals.sort((a, b) {
        DateTime? dateA = _parseDate(a.value);
        DateTime? dateB = _parseDate(b.value);
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });
      return vals.first;
    }

    return vals.first;
  }

  /// Tarih metinlerini standart DateTime nesnesine çevirir.
  DateTime? _parseDate(String dateStr) {
    final cleanDate = dateStr.replaceAll('/', '.').replaceAll('-', '.');
    final formats = [
      DateFormat('dd.MM.yyyy'),
      DateFormat('dd.MM.yy'),
    ];
    for (final format in formats) {
      try {
        return format.parseStrict(cleanDate);
      } catch (_) {}
    }
    return null;
  }


  double Function(Rect, Rect) _getScorer(String name) {
    switch (name) {
      case 'findRight':
        return _scoreRightOf;
      case 'findLeft':
        return _scoreLeftOf;
      case 'findBelow':
        return _scoreBelow;
      default:
        return (a, b) => double.infinity;
    }
  }
  // Lütfen bu 3 fonksiyonu da kopyalayıp eskileriyle değiştirin.

// _scoreRightOf fonksiyonu güncellendi
  double _scoreRightOf(Rect k, Rect v) {
    // Dikey hizalama toleransı %50'den %30'a düşürüldü.
    final yOverlap = math.max(0.0, math.min(k.bottom, v.bottom) - math.max(k.top, v.top));
    if (yOverlap < (k.height * 0.3)) return double.infinity;

    final dx = v.left - k.right;
    // Değerin, etiketin soluna hafifçe (%15 kadar) taşmasına izin verilir.
    if (dx < -k.width * 0.15) return double.infinity;

    // Mutlak değer kullanılarak hem sağındaki hem de hafifçe solundaki adaylar değerlendirilir.
    return dx.abs();
  }

// _scoreLeftOf fonksiyonu güncellendi
  double _scoreLeftOf(Rect k, Rect v) {
    // Dikey hizalama toleransı %50'den %30'a düşürüldü.
    final yOverlap = math.max(0.0, math.min(k.bottom, v.bottom) - math.max(k.top, v.top));
    if (yOverlap < (k.height * 0.3)) return double.infinity;

    final dx = k.left - v.right;
    // Değerin, etiketin sağına hafifçe (%15 kadar) taşmasına izin verilir.
    if (dx < -k.width * 0.15) return double.infinity;

    return dx.abs();
  }

// _scoreBelow fonksiyonu güncellendi
  double _scoreBelow(Rect k, Rect v) {
    // Yatay hizalama toleransı artırılarak farklı sütun genişliklerine uyum sağlandı.
    final horizontallyAligned = (v.center.dx - k.center.dx).abs() < (k.width * 1.5);

    // Değerin etiketin altında olduğundan emin ol
    if (!horizontallyAligned || v.top <= k.bottom) return double.infinity;

    // Dikey mesafeyi döndür
    return v.top - k.bottom;
  }

  // ───────────────────────────── UI HELPERS & POPULATE
  void _populateFields(Map<String, String> d) {
    setState(() {
      if (d['installationId'] != null) _installationIdCtrl.text = d['installationId']!;
      if (d['invoiceAmount'] != null) {
        _invoiceAmountCtrl.text = d['invoiceAmount']!
            .replaceAll('.', '')
            .replaceAll(',', '.');
      }
      if (d['readingValue'] != null) {
        _valueCtrl.text = d['readingValue']!;
      }
      if (d['dueDate'] != null) {
        final String ds = d['dueDate']!.replaceAll('/', '.').replaceAll('-', '.');
        try {
          _pickedDueDate = DateFormat('dd.MM.yyyy').parseStrict(ds);
        } catch (_) {
          try {
            _pickedDueDate = DateFormat('yyyy.MM.dd').parseStrict(ds);
          } catch (e) {
            print('Tarih formatı anlaşılamadı: $ds');
          }
        }
      }
    });
  }

  // ───────────────────── LOCATION & SAVE/UPDATE
  Future<void> _handleLocationPermission() async {
    setState(() => _isGettingLocation = true);
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum servisleri kapalı.')));
      }
      setState(() => _isGettingLocation = false);
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum izni verilmedi.')));
      }
      setState(() => _isGettingLocation = false);
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      String address =
          'Lat: ${pos.latitude.toStringAsFixed(5)}, Lng: ${pos.longitude.toStringAsFixed(5)}';
      try {
        final placemark =
        await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemark.isNotEmpty) {
          final p = placemark.first;
          address =
              [p.street, p.locality, p.country].where((e) => e != null && e.isNotEmpty).join(', ');
        }
      } catch (_) {}
      setState(() {
        _gpsPos = pos;
        _locationTextCtrl.text = address;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Konum alınamadı: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _saveOrUpdate() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Giriş yapmalısınız.');

      final readingValue = double.tryParse(
          _valueCtrl.text.trim().replaceAll(RegExp(r'[.,]'), '')) ?? 0.0;

      final invoiceAmount =
      double.tryParse(_invoiceAmountCtrl.text.trim().replaceAll(',', '.'));
      final data = {
        'meterName': _meterNameCtrl.text.trim().isEmpty
            ? null
            : _meterNameCtrl.text.trim(),
        'installationId': _installationIdCtrl.text.trim(),
        'readingValue': readingValue,
        'readingTime': _pickedTime,
        'unit': _selectedUnit.first,
        'locationText': _locationTextCtrl.text.trim().isEmpty
            ? null
            : _locationTextCtrl.text.trim(),
        'gpsLat': _gpsPos?.latitude,
        'gpsLng': _gpsPos?.longitude,
        'invoiceAmount': invoiceAmount,
        'dueDate': _pickedDueDate,
        'dueAmount': null,
      };
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('readings');
      final msg = _isEdit
          ? 'Kayıt başarıyla güncellendi.'
          : 'Sayaç okuması başarıyla kaydedildi.';
      if (_isEdit) {
        await ref.doc(widget.readingToEdit!.id).update(data);
      } else {
        await ref.add(data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bir hata oluştu: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  // ────────────────────────────── UI ──────────────────────────────── //

  void _showScanTipsDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Daha İyi Tarama İçin İpuçları'),
      content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• Faturayı düz bir yüzeye koyun'),
          Text('• İyi ışık altında fotoğraf çekin'),
          Text('• Faturanın tamamı görünür olsun'),
          Text('• Buruşukluklardan kaçının'),
          Text('• Kamera sabit tutun'),
          Text('• Gerekirse birkaç kez deneyin'),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Anladım'))],
    ),
    );
  }

  void _showManualInputDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Manuel Giriş'),
      content: const Text('Bu özellik yakında eklenecektir. Lütfen şimdilik alanları elle doldurun.'),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam'))],
    ),
    );
  }

  void _showOcrDebugDialog(String ocrText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OCR Sonucu (Debug)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              Text('Tespit edilen metin uzunluğu: ${ocrText.length} karakter'),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    ocrText,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // DEĞİŞİKLİK: Kopyala butonu işlevsel hale getirildi.
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: ocrText));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Metin panoya kopyalandı.')));
                      Navigator.of(context).pop();
                    },
                    child: const Text('Kopyala'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Okumayı Düzenle' : 'Yeni Sayaç Okuma'),
        actions: [
          if (_isScanning)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)))
          else ...[
            IconButton(icon: const Icon(Icons.camera_alt_outlined), tooltip: 'Faturayı Tara', onPressed: _scanWithOcr),
            // DEĞİŞİKLİK: PopupMenuButton güncellendi.
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'manual_scan': _showManualInputDialog(); break;
                  case 'scan_tips': _showScanTipsDialog(); break;
                  case 'show_debug':
                    if (_lastOcrResultText != null) {
                      _showOcrDebugDialog(_lastOcrResultText!);
                    }
                    break;
                }
              },
              itemBuilder: (context) {
                final menuItems = <PopupMenuEntry<String>>[
                  const PopupMenuItem(
                    value: 'manual_scan',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Manuel Giriş'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'scan_tips',
                    child: ListTile(
                      leading: Icon(Icons.help_outline),
                      title: Text('Tarama İpuçları'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ];
                // Yalnızca bir tarama yapıldıysa debug menüsünü göster
                if (_lastOcrResultText != null) {
                  menuItems.add(const PopupMenuDivider());
                  menuItems.add(
                    const PopupMenuItem(
                      value: 'show_debug',
                      child: ListTile(
                        leading: Icon(Icons.bug_report_outlined),
                        title: Text('Son Taramayı Göster (Debug)'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                }
                return menuItems;
              },
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _meterNameCtrl, decoration: const InputDecoration(labelText: 'Sayaç Adı (örn: Ev Elektrik)', prefixIcon: Icon(Icons.label_important_outline), border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _installationIdCtrl, decoration: const InputDecoration(labelText: 'Tesisat Numarası', prefixIcon: Icon(Icons.confirmation_number_outlined), border: OutlineInputBorder()), validator: (v) => v!.trim().isEmpty ? 'Tesisat numarası zorunludur' : null),
              const SizedBox(height: 16),
              TextFormField(
                controller: _valueCtrl,
                decoration: const InputDecoration(labelText: 'Okuma Değeri', prefixIcon: Icon(Icons.speed_outlined), border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Okuma değeri girin';
                  if (double.tryParse(v.trim().replaceAll(RegExp(r'[.,]'), '')) == null) return 'Lütfen geçerli bir sayı girin';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'kWh', label: Text('kWh'), icon: Icon(Icons.electric_bolt)),
                  ButtonSegment(value: 'm³', label: Text('m³'), icon: Icon(Icons.water_drop)),
                ],
                selected: _selectedUnit,
                onSelectionChanged: (s) => setState(() => _selectedUnit = s),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)),
                leading: const Icon(Icons.today),
                title: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Okuma Zamanı', style: Theme.of(context).textTheme.bodySmall),
                    Text(DateFormat('dd MMMM HH:mm', 'tr_TR').format(_pickedTime), style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _pickedTime, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), locale: const Locale('tr', 'TR'));
                  if (d == null) return;
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_pickedTime));
                  if (t == null) return;
                  setState(() => _pickedTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationTextCtrl,
                decoration: InputDecoration(
                  labelText: 'Adres / Lokasyon',
                  border: const OutlineInputBorder(),
                  prefixIcon: _isGettingLocation ? const Padding(padding: EdgeInsets.all(10.0), child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(icon: const Icon(Icons.my_location), onPressed: _handleLocationPermission),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 10),
              Text('Fatura Bilgileri (Opsiyonel)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(controller: _invoiceAmountCtrl, decoration: const InputDecoration(labelText: 'Fatura Tutarı', prefixIcon: Icon(Icons.receipt_long_outlined), border: OutlineInputBorder(), suffixText: 'TL'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)),
                leading: const Icon(Icons.event_busy),
                title: Text(_pickedDueDate == null ? 'Son Ödeme Tarihi Seçin' : DateFormat('dd MMMM yyyy', 'tr_TR').format(_pickedDueDate!)),
                trailing: _pickedDueDate == null ? const Icon(Icons.calendar_month) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _pickedDueDate = null)),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _pickedDueDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), locale: const Locale('tr', 'TR'));
                  if (d == null) return;
                  setState(() => _pickedDueDate = d);
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveOrUpdate,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: _isSaving ? Colors.grey : Theme.of(context).primaryColor, foregroundColor: Colors.white),
                icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(_isEdit ? Icons.check : Icons.save),
                label: Text(_isEdit ? 'Güncelle' : 'Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}