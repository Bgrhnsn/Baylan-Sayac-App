// lib/new_reading_screen.dart
// ===========================================================
// yeni fatura ekleme alanı google ml kit bağlandı
// ml kit ile algılanan metin regex kurallarından geçerek istediğimiz verileri almaya çalışır
// GÜNCELLEME: Fatura görseli Firebase Storage'a kaydediliyor ve önizlemesi gösteriliyor.
// ===========================================================

import 'dart:io';//dosya işlemleri
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dart:math' as math;//matematiksel işlemler

import 'package:cloud_firestore/cloud_firestore.dart';//firebase veritabanına veri kaydetmek
import 'package:flutter/material.dart';//temel görsel bileşenler
import 'package:firebase_auth/firebase_auth.dart';//kimlik doğrulama için
import 'package:firebase_storage/firebase_storage.dart'; // Görsel kaydı için eklendi.
import 'package:flutter/services.dart'; // temel servislere erişim hata ayıklama ekranı için
import 'package:geocoding/geocoding.dart';//lokasyon
import 'package:geolocator/geolocator.dart';//lokasyon
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';//kamera butonuna basılınca çıkan ekran
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';//ocr
import 'package:intl/intl.dart';//tarih ve sayıları farklı formata almak için
import 'package:sayacfaturapp/models/meter_reading.dart';//model importu
import 'package:sayacfaturapp/theme/custom_components.dart';//ortak tema
import 'package:shared_preferences/shared_preferences.dart';//pop up mesajı için gerekli kütüphane

// ———————————————————————————————————————————  Helpers
class _ParseResult {
  final Map<String, String> data;
  final String? detectedProvider; // 'izsu', 'gediz' veya null olabilir

  _ParseResult({required this.data, this.detectedProvider});
}
class _Candidate {//aranan bilgi olmaya adayları seçme
  _Candidate({required this.value, required this.boundingBox, this.score = 0});
  final String value;//metin
  final Rect boundingBox;//metin faturanın neresinde
  double score;//aday ne kadar doğru
}
class _LineInfo {//ocr dan gelen her bir metin parçasını , orjinal ve temizlenmiş ve konumunu pakette tutar
  _LineInfo(this.text, this.normalizedText, this.boundingBox);
  final String text;//orjinal metin
  final String normalizedText;//normalleştirilmiş metin
  final Rect boundingBox;//metnin konumu
}

double _toDouble(String s) =>//12548,2655 -> 12548.2655
double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

//
class NewReadingScreen extends StatefulWidget {
  const NewReadingScreen({super.key, this.readingToEdit});
  final MeterReading? readingToEdit;
  @override
  State<NewReadingScreen> createState() => _NewReadingScreenState();
}

class _NewReadingScreenState extends State<NewReadingScreen> {//dinamik
  // controllers
  final _formKey = GlobalKey<FormState>();//kaydet butonuna basınca doğrulama kontorlü
  final _meterNameCtrl = TextEditingController();
  final _installationIdCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _locationTextCtrl = TextEditingController();
  final _invoiceAmountCtrl = TextEditingController();

  // state
  File? _scannedImageFile; // Cihazda taranan ve henüz yüklenmemiş görsel dosyası.
  String? _existingInvoiceImageUrl; // Düzenleme modunda, Firestore'dan gelen mevcut görselin URL'si.
  DateTime _pickedTime = DateTime.now();
  DateTime? _pickedDueDate;//son ödeme tarihi
  Set<String> _selectedUnit = {'kWh'};
  Position? _gpsPos;
  bool _isGettingLocation = false;//konum alırken ki animasyon
  bool _isSaving = false;//kayıt ederkenki animasyon
  bool _isScanning = false;//tarama ekranına geçerken ki animasyon
  bool get _isEdit => widget.readingToEdit != null;//veri düzenleme işlemi yeni kayıt mı düzenlememi mi
  String? _lastOcrResultText; // Son OCR sonucunu saklamak için.

  // ---------------------------------------------------- lifecycle
  @override
  void initState() {//ekranın yaşam döngüsünü yönetir
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
      _existingInvoiceImageUrl = r.invoiceImageUrl;
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
  void dispose() {//ekran kapanınca controllerları hafızadan silme
    _meterNameCtrl.dispose();
    _installationIdCtrl.dispose();
    _valueCtrl.dispose();
    _locationTextCtrl.dispose();
    _invoiceAmountCtrl.dispose();
    super.dispose();
  }

  // OCR ve documentscanner
  // Lütfen mevcut _scanWithOcr fonksiyonunuzu silip,
// yerine bu güncellenmiş versiyonu yapıştırın.

  Future<void> _scanWithOcr() async {
    var status = await Permission.photos.status;
    if (status.isDenied) {
      status = await Permission.photos.request();
    }
    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Galeri izni reddedildi. Lütfen uygulama ayarlarından izin verin.'),
        ));
      }
      return;
    }
    if (!status.isGranted) return;

    final scanner = DocumentScanner(options: DocumentScannerOptions(
      documentFormat: DocumentFormat.jpeg,
      mode: ScannerMode.filter,
      pageLimit: 1,
      isGalleryImport: true,
    ));

    setState(() => _isScanning = true);

    try {
      final result = await scanner.scanDocument();
      if (result.images.isEmpty) {
        await scanner.close();
        if(mounted) setState(() => _isScanning = false);
        return;
      }

      final srcPath = result.images.first;
      final tempDir = await getTemporaryDirectory();
      final dstPath = '${tempDir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final copiedImg = await File(srcPath).copy(dstPath);

      if (mounted) {
        setState(() {
          _scannedImageFile = copiedImg;
          _existingInvoiceImageUrl = null;
        });
      }

      await scanner.close();

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recText = await recognizer.processImage(InputImage.fromFile(copiedImg));
      await recognizer.close();

      // --- GÜNCELLEME BURADA BAŞLIYOR ---

      // 1. Artık _parse'dan gelen "paketi" alıyoruz.
      final parseResult = _parse(recText);
      // 2. Paketin içinden veri "sözlüğünü" çıkarıyoruz.
      final data = parseResult.data;

      // 3. Paketin içindeki fatura tipine göre birimi otomatik seçiyoruz.
      if (parseResult.detectedProvider == 'izsu') {
        setState(() {
          _selectedUnit = {'m³'}; // İZSU için m³ seç
        });
      } else if (parseResult.detectedProvider == 'gediz') {
        setState(() {
          _selectedUnit = {'kWh'}; // Gediz için kWh seç
        });
      }
      // Varsayılan durumda bir şey yapmıyoruz, kullanıcının seçimine bırakıyoruz.

      // 4. Alanları dolduruyoruz.
      _populateFields(data);

      // --- GÜNCELLEME BURADA BİTİYOR ---

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data.isEmpty
              ? 'Faturadan otomatik bilgi alınamadı.'
              : '${data.length} alan dolduruldu: ${data.keys.join(', ')}'),
          backgroundColor: data.isEmpty ? Colors.orange : Colors.green,
        ));
      }
    } on PlatformException catch (e) {
      if (e.message?.toLowerCase().contains('cancelled') ?? false) {
        print('Kullanıcı tarama işlemini iptal etti.');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bir platform hatası oluştu: $e')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bir hata oluştu: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }
  Future<void> _onCameraPressed() async {
    final prefs = await SharedPreferences.getInstance();
    // Cihaz hafızasından 'hasSeenScanTips' değerini oku. Eğer yoksa 'false' kabul et.
    final hasSeenTips = prefs.getBool('hasSeenScanTips') ?? false;

    if (!hasSeenTips && mounted) {
      // Eğer kullanıcı ipuçlarını daha önce görmemişse, dialogu göster.
      _showScanTipsDialog(
        onContinue: () async {
          // Kullanıcı "Anladım, Tara" butonuna basınca,
          // ipuçlarını gördüğünü hafızaya kaydet ve taramayı başlat.
          await prefs.setBool('hasSeenScanTips', true);
          _scanWithOcr();
        },
      );
    } else {
      // Kullanıcı ipuçlarını zaten görmüş, doğrudan taramayı başlat.
      _scanWithOcr();
    }

  }

  // ————————————————————————————————  Normalization & Parsing (Bu kısım değişmedi)
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

  // Bu, _parse fonksiyonunun GÜNCELLENMİŞ halidir.

  _ParseResult _parse(RecognizedText rec) {
    final elements = rec.blocks
        .expand((b) => b.lines
        .expand((l) => l.elements.map((e) => _LineInfo(e.text, _norm(e.text), e.boundingBox))))
        .toList();

    // --- (izsuSpecs ve gedizSpecs tanımlarınız burada aynı kalacak) ---
    final izsuSpecs = {
      'installationId': {'strategies': ['findRight', 'findBelow'], 'kw': ['sayaç','sayac','sayaç no','sayac no'], 're': [RegExp(r'(\b\d{7,14}\b)')], 'negKw': ['vergi', 'dosya', 'tc kimlik', 'fatura', 'musteri','abone'],},
      'invoiceAmount': {'strategies': ['findBelow', 'findRight'], 'kw': ['odenecek toplam tutar'], 're': [RegExp(r'(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})')], 'negKw': ['kdv', 'yuvarlama', 'bedel', 'taksit', 'donem tutari', 'ara toplam', 'izsu fatura toplami', 'toplam', 'su tuketim'], 'lineFilter': (String raw) => RegExp(r'[.,]\d{2}\b').hasMatch(raw),},
      'dueDate': {'strategies': ['findRight','findBelow'], 'kw': ['son odeme tarihi', 's o t','son ödeme tarihi','SON ÖDEME TARİHİ','SON ODEME TARİHİ','SON ODEME TARIHI'], 're': [RegExp(r'(\d{2}[./-]\d{2}[./-]\d{2,4})')], 'negKw': ['okuma','OKUMA','ilk'],},
      'readingValue': {'strategies': ['findRight'], 'kw': ['tuketim'], 're': [RegExp(r'^\d+$')], 'negKw': ['su bedeli', 'tüketim gün say', 'ilk endeks', 'son endeks', 'su birim fiyat', 'atık su birim fiyat', 'bölge kodu', 'tutar', 'toplam', 'kdv', 'kademe', 'endeks', 'oran'],},
    };
    final gedizSpecs = {
      'installationId': {'strategies': ['findBelow'], 'kw': ['tekil kod/tesisat no','tesisat no', 'tekil kod','tekil','tesisat'], 're': [RegExp(r'(\b\d{7,14}\b)')], 'negKw': ['vergi', 'dosya', 'tc kimlik', 'fatura','seri','sozlesme hesap','sozleşme','sözleşme'],},
      'invoiceAmount': {'strategies': ['findBelow'], 'kw': ['odenecek tutar', 'toplam fatura tutari','ödenecek tutar','tutar'], 're': [RegExp(r'(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})')], 'negKw': ['kdv', 'yuvarlama', 'bedel', 'taksit', 'donem tutari'], 'lineFilter': (String raw) => RegExp(r'[.,]\d{2}\b').hasMatch(raw),},
      'dueDate': {'strategies': ['findBelow'], 'kw': ['son odeme tarihi', 's o t','son ödeme tarihi','son odeme tarıhı'], 're': [RegExp(r'(\d{2}[./-]\d{2}[./-]\d{2,4})')], 'negKw': ['fatura tarihi', 'okuma tarihi', 'ilk okuma', 'son okuma'],},
      'readingValue': {'strategies': ['findRight'], 'kw': ['tüketim(kwh)','tüketim', 'enerji tuketim bedeli','tuketim'], 're': [RegExp(r'\b\d{1,3}(?:\.\d{3})*,\d{3}\b')], 'negKw': ['fiyat', 'oran', 'tl', 'kr', 'krs', 'bedel(tl)', 'yüksek kademe', 'yuksek kademe', 'gece', 'gunduz', 'puant', 'tek zaman', 'endeks', 'indeks', 'fark', 'ortalama', 'sayac no', 'abone no', 'tesisat no', 'fatura no', 'kwh', 'gun say', 'gün say' ,'ödenecek tutar','tutar','fatura kodu','elektrik faturası','fatura', 'fatura otalama'],},
    };
    // --------------------------------------------------------------------

    final fullText = _norm(rec.text);
    Map<String, dynamic> specs;
    // YENİ: Tespit edilen fatura tipini saklamak için bir değişken
    String? detectedProvider;

    if (fullText.contains('izsu')) {
      print("İZSU Fatura Profili Seçildi.");
      specs = izsuSpecs;
      detectedProvider = 'izsu'; // <-- Tipi değişkene ata
    } else if (fullText.contains('gediz')) {
      print("Gediz Fatura Profili Seçildi.");
      specs = gedizSpecs;
      detectedProvider = 'gediz'; // <-- Tipi değişkene ata
    } else {
      print("Varsayılan (Gediz) Fatura Profili Seçildi.");
      specs = gedizSpecs;
      detectedProvider = null; // <-- Bilinmeyen tip için null ata
    }

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
      out['readingValue'] = out['readingValue']!
          .replaceAll(' ', '')
          .replaceAll(RegExp(r'\s*(kwh|m3|m³)', caseSensitive: false), '')
          .trim();
    }

    // YENİ: Sonuçları ve tespit edilen fatura tipini birlikte döndür
    return _ParseResult(data: out, detectedProvider: detectedProvider);
  }

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

  double _scoreRightOf(Rect k, Rect v) {
    final yOverlap = math.max(0.0, math.min(k.bottom, v.bottom) - math.max(k.top, v.top));
    if (yOverlap < (k.height * 0.3)) return double.infinity;

    final dx = v.left - k.right;
    // Değerin, etiketin soluna hafifçe (%15 kadar) taşmasına izin verilir.
    if (dx < -k.width * 0.15) return double.infinity;

    // Mutlak değer kullanılarak hem sağındaki hem de hafifçe solundaki adaylar değerlendirilir.
    return dx.abs();
  }

  double _scoreLeftOf(Rect k, Rect v) {
    final yOverlap = math.max(0.0, math.min(k.bottom, v.bottom) - math.max(k.top, v.top));
    if (yOverlap < (k.height * 0.3)) return double.infinity;

    final dx = k.left - v.right;
    // Değerin, etiketin sağına hafifçe (%15 kadar) taşmasına izin verilir.
    if (dx < -k.width * 0.15) return double.infinity;

    return dx.abs();
  }

  double _scoreBelow(Rect k, Rect v) {
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

  // EKLENDİ: Fatura görselini Firebase Storage'a yükleyen fonksiyon.
  // LÜTFEN MEVCUT _uploadInvoiceImage FONKSİYONUNUZU SİLİP BUNU YAPIŞTIRIN

  // lib/screens/new_reading_screen.dart içine yapıştırılacak kod

  Future<String?> _uploadInvoiceImage(File imageFile, String userId) async {
    print('--- [DEBUG] YÜKLEME FONKSİYONU BAŞLADI ---');
    try {
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      print('--- [DEBUG] 1. Adım: Dosya Adı: $fileName');

      final ref = FirebaseStorage.instance.ref()
          .child('invoice_images')
          .child(userId) // <-- KULLANICININ KİMLİĞİYLE BİR KLASÖR OLUŞTURUYORUZ
          .child(fileName); print('--- [DEBUG] 2. Adım: Storage Referansı: ${ref.fullPath}');

      print('--- [DEBUG] 3. Adım: Dosya Yükleme Başlıyor (putFile)...');
      UploadTask uploadTask = ref.putFile(imageFile);

      TaskSnapshot snapshot = await uploadTask;
      print('--- [DEBUG] 4. Adım: Dosya Yükleme Tamamlandı!');

      print('--- [DEBUG] 5. Adım: İndirme URL\'si Alınıyor (getDownloadURL)...');
      final downloadUrl = await snapshot.ref.getDownloadURL();
      print('--- [DEBUG] 6. Adım: URL Başarıyla Alındı!');
      print('--- [DEBUG] YÜKLEME BAŞARILI ---');
      return downloadUrl;

    } catch (e, s) {
      print('!!!!!!!!!!      YÜKLEME HATASI      !!!!!!!!!!');
      print('HATA MESAJI: $e');
      if (e is FirebaseException) {
        print('FIREBASE HATA KODU: ${e.code}');
        print('FIREBASE HATA AÇIKLAMASI: ${e.message}');
      }
      print('STACK TRACE (Teknik Hata Detayı):');
      print(s);
      return null;
    }
  }

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

  // GÜNCELLENDİ: Kaydetme fonksiyonu görsel yüklemeyi içerecek şekilde tamamen değiştirildi.
  Future<void> _saveOrUpdate() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Giriş yapmalısınız.');

      String? invoiceImageUrl = _existingInvoiceImageUrl;

      // Eğer yeni bir görsel taranmışsa, onu yükle.
      if (_scannedImageFile != null) {
        invoiceImageUrl = await _uploadInvoiceImage(_scannedImageFile!, user.uid);
        if (invoiceImageUrl == null) {
          // Yükleme başarısız olursa işlemi durdur.
          throw Exception("Görsel yüklenemediği için kayıt başarısız.");
        }
      }

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
        'invoiceImageUrl': invoiceImageUrl, // Veritabanına görsel URL'sini ekle
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

  void _showScanTipsDialog({VoidCallback? onContinue}) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Tarama İpuçları'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('En iyi sonuçlar için:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('• Faturayı düz bir yüzeye koyun.'),
              SizedBox(height: 4),
              Text('• Parlama ve gölgelerden kaçının.'),
              SizedBox(height: 4),
              Text('• Faturanın tamamı kameraya sığsın.'),
              SizedBox(height: 4),
              Text('• Kamerayı sabit tutun.'),
            ],
          ),
          actions: [
            // Eğer onContinue metodu verilmişse, "Anladım, Tara" butonu gösterilir.
            // Verilmemişse, sadece "Anladım" butonu gösterilir.
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (onContinue != null) {
                  onContinue();
                }
              },
              child: Text(onContinue != null ? 'Anladım, Tara' : 'Anladım'),
            ),
          ],
        );
      },
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

  // EKLENDİ: Fatura görseli önizlemesini gösteren widget.
  Widget _buildInvoicePreview() {
    if (_scannedImageFile == null && _existingInvoiceImageUrl == null) {
      return const SizedBox.shrink();
    }

    ImageProvider imageProvider;
    if (_scannedImageFile != null) {
      imageProvider = FileImage(_scannedImageFile!);
    } else {
      imageProvider = NetworkImage(_existingInvoiceImageUrl!);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Fatura Görseli", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: imageProvider,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 150,
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() {
                        _scannedImageFile = null;
                        _existingInvoiceImageUrl = null;
                      });
                    },
                    tooltip: 'Görseli Kaldır',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Okumayı Düzenle' : 'Yeni Sayaç Okuma'),
        actions: [
          if (_isScanning)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)))
          else ...[
            IconButton(
                icon: const Icon(Icons.camera_alt_outlined),
                tooltip: 'Faturayı Tara',
                onPressed: _scanWithOcr, ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'scan_tips':_showScanTipsDialog(); break;
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
                    value: 'scan_tips',
                    child: ListTile(
                      leading: Icon(Icons.help_outline),
                      title: Text('Tarama İpuçları'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ];
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
              // GÜNCELLENDİ: Formun en başına fatura görseli önizlemesi eklendi.
              _buildInvoicePreview(),

              TextFormField(controller: _meterNameCtrl, decoration: const InputDecoration(labelText: 'Sayaç Adı (örn: Ev Elektrik)', prefixIcon: Icon(Icons.label_important_outline))),
              const SizedBox(height: 16),
              TextFormField(controller: _installationIdCtrl, decoration: const InputDecoration(labelText: 'Tesisat Numarası', prefixIcon: Icon(Icons.confirmation_number_outlined)), validator: (v) => v!.trim().isEmpty ? 'Tesisat numarası zorunludur' : null),
              const SizedBox(height: 16),
              TextFormField(
                controller: _valueCtrl,
                decoration: const InputDecoration(labelText: 'Okuma Değeri', prefixIcon: Icon(Icons.speed_outlined)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Okuma değeri girin';
                  if (double.tryParse(v.trim().replaceAll(RegExp(r'[.,]'), '')) == null) return 'Lütfen geçerli bir sayı girin';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
                  selectedForegroundColor: theme.colorScheme.onPrimary,
                  selectedBackgroundColor: theme.colorScheme.primary,
                ),
                segments: const [
                  ButtonSegment(value: 'kWh', label: Text('kWh'), icon: Icon(Icons.electric_bolt)),
                  ButtonSegment(value: 'm³', label: Text('m³'), icon: Icon(Icons.water_drop)),
                ],
                selected: _selectedUnit,
                onSelectionChanged: (s) => setState(() => _selectedUnit = s),
              ),
              const SizedBox(height: 16),
              AppStyledCard(
                child: ListTile(
                  leading: const Icon(Icons.today_outlined),
                  title: Text('Okuma Zamanı', style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                      DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR').format(_pickedTime),
                      style: theme.textTheme.titleMedium
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _pickedTime, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d == null) return;
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_pickedTime));
                    if (t == null) return;
                    setState(() => _pickedTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
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
              AppStyledCard(
                child: ListTile(
                  leading: const Icon(Icons.today_outlined),
                  title: Text('Okuma Zamanı', style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                      DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR').format(_pickedTime),
                      style: theme.textTheme.titleMedium
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _pickedTime, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d == null) return;
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_pickedTime));
                    if (t == null) return;
                    setState(() => _pickedTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveOrUpdate,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(_isEdit ? Icons.check_circle_outline : Icons.save_outlined),
                label: Text(_isEdit ? 'Güncelle' : 'Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}