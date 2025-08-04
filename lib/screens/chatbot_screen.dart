import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Mesajları modellemek için basit bir sınıf
class ChatMessage {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? toolCall;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.toolCall,
  });
}

class ChatbotScreen extends StatefulWidget {
  final String userId;
  const ChatbotScreen({super.key, required this.userId});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _conversationHistory = [];
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isHistoryLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// Firestore'dan konuşma geçmişini yükleyen fonksiyon
  Future<void> _loadHistory() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('chatbot_history')
          .orderBy('timestamp')
          .get();

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          data.remove('timestamp');
          _conversationHistory.add(data);

          final role = data['role'];
          final parts = data['parts'][0];
          if (role == 'user') {
            _messages.add(ChatMessage(text: parts['text'], isUser: true));
          } else if (role == 'model' && parts.containsKey('text')) {
            _messages.add(ChatMessage(text: parts['text'], isUser: false));
          }
        }
      } else {
        _addWelcomeMessage();
      }

    } catch (e) {
      _messages.add(ChatMessage(text: "Geçmiş yüklenirken bir hata oluştu.", isUser: false));
    } finally {
      setState(() {
        _isHistoryLoading = false;
      });
    }
  }

  /// Konuşmanın bir parçasını Firestore'a kaydeden fonksiyon
  Future<void> _savePartToHistory(Map<String, dynamic> part) async {
    final Map<String, dynamic> partToSave = Map.from(part);
    partToSave['timestamp'] = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('chatbot_history')
        .add(partToSave);
  }

  /// Hem lokal hem de Firestore'daki geçmişi temizleyen fonksiyon
  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geçmişi Sil'),
        content: const Text('Tüm sohbet geçmişiniz kalıcı olarak silinecektir. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      final collection = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('chatbot_history');
      final snapshot = await collection.get();
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      _conversationHistory.clear();
      _messages.clear();
      _addWelcomeMessage();

      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Karşılama mesajını eklemek için yardımcı fonksiyon
  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      text: "Merhaba! Ben Asistan. Fatura kaydı oluşturabilir, silebilir, güncelleyebilir veya faturalar için analiz yapmamı isteyebilirsiniz.",
      isUser: false,
    ));
  }

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;

    final userMessageText = _controller.text;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: userMessageText, isUser: true));
      _isLoading = true;
    });

    final userMessageMap = {
      'role': 'user',
      'parts': [{'text': userMessageText}]
    };
    _conversationHistory.add(userMessageMap);
    await _savePartToHistory(userMessageMap);

    await _getAndProcessResponse();
  }

  Future<void> _getAndProcessResponse() async {
    try {
      final responseData = await getGeminiResponse(_conversationHistory);

      if (responseData.containsKey('functionCall')) {
        final functionCall = responseData['functionCall'];
        final functionName = functionCall['name'];
        final args = functionCall['args'] as Map<String, dynamic>;

        final modelFunctionCallPart = {'role': 'model', 'parts': [{'functionCall': functionCall}]};
        _conversationHistory.add(modelFunctionCallPart);
        await _savePartToHistory(modelFunctionCallPart);

        final functionResult = await _handleFunctionCall(functionName, args);

        final functionResponsePart = {'role': 'function', 'parts': [{'functionResponse': {'name': functionName, 'response': {'result': functionResult}}}]};
        _conversationHistory.add(functionResponsePart);
        await _savePartToHistory(functionResponsePart);

        await _getAndProcessResponse();

      } else {
        final botResponseText = responseData['text'];
        final botMessage = ChatMessage(text: botResponseText, isUser: false);

        setState(() {
          _messages.add(botMessage);
          _isLoading = false;
        });

        final modelTextPart = {'role': 'model', 'parts': [{'text': botResponseText}]};
        _conversationHistory.add(modelTextPart);
        await _savePartToHistory(modelTextPart);
      }
    } catch (e) {
      final errorMessage = ChatMessage(text: "Üzgünüm, bir hata oluştu: $e", isUser: false);
      setState(() {
        _messages.add(errorMessage);
        _isLoading = false;
      });
    }
  }

  /// Gemini'den gelen fonksiyon çağrısını işler.
  Future<dynamic> _handleFunctionCall(String functionName, Map<String, dynamic> args) async {
    switch (functionName) {
      case 'getConsumptionAnalysis':
        return await _getConsumptionAnalysis(
          periodInMonths: (args['periodInMonths'] as num?)?.toInt(),
          dataType: args['dataType'] as String?,
          analysisType: args['analysisType'] as String?,
        );
      case 'createNewReading':
        DateTime? dueDate;
        if (args['dueDate'] != null) {
          try { dueDate = DateTime.parse(args['dueDate'] as String); } catch (e) { /* Hata yok sayıldı */ }
        }
        return await _createNewReading(
          readingValue: (args['readingValue'] as num?)?.toDouble(),
          invoiceAmount: (args['invoiceAmount'] as num?)?.toDouble(),
          unit: args['unit'] as String?,
          meterName: args['meterName'] as String?,
          installationId: args['installationId'] as String?,
          dueDate: dueDate,
          confirmed: args['confirmed'] as bool? ?? false,
        );
      case 'deleteReading':
        return await _deleteReading(
          installationId: args['installationId'] as String?,
          confirmed: args['confirmed'] as bool? ?? false,
        );
      case 'updateReading':
        return await _updateReading(
          installationId: args['installationId'] as String?,
          fieldsToUpdate: args['fieldsToUpdate'] as Map<String, dynamic>?,
          confirmed: args['confirmed'] as bool? ?? false,
        );
      default:
        return "Bilinmeyen fonksiyon: $functionName";
    }
  }

  /// Bir kaydı silen fonksiyon
  Future<String> _deleteReading({String? installationId, bool confirmed = false}) async {
    if (installationId == null) {
      return "Hangi kaydı silmek istediğinizi belirtmek için lütfen tesisat numarasını veya sayaç adını söyleyin.";
    }

    final query = FirebaseFirestore.instance
        .collection('users').doc(widget.userId).collection('readings')
        .where('installationId', isEqualTo: installationId)
        .orderBy('readingTime', descending: true).limit(1);

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) {
      return "$installationId tesisat numarasına ait bir kayıt bulunamadı.";
    }
    final docToDelete = snapshot.docs.first;

    if (!confirmed) {
      final data = docToDelete.data();
      final readingValue = data['readingValue'];
      final unit = data['unit'];
      final date = (data['readingTime'] as Timestamp).toDate();
      final formattedDate = DateFormat('dd MMMM yyyy', 'tr_TR').format(date);
      return "Tesisat No: $installationId, Değer: $readingValue $unit, Tarih: $formattedDate olan kaydı silmek istediğinizden emin misiniz?";
    }

    try {
      await docToDelete.reference.delete();
      return "$installationId tesisat numaralı kayıt başarıyla silindi.";
    } catch (e) {
      return "Kayıt silinirken bir hata oluştu: $e";
    }
  }

  /// GÜNCELLEME: Bir kaydı güncelleyen fonksiyon, artık tarih formatını düzeltiyor.
  Future<String> _updateReading({String? installationId, Map<String, dynamic>? fieldsToUpdate, bool confirmed = false}) async {
    if (installationId == null) {
      return "Hangi kaydı güncellemek istediğinizi belirtmek için lütfen tesisat numarasını veya sayaç adını söyleyin.";
    }
    if (fieldsToUpdate == null || fieldsToUpdate.isEmpty) {
      return "Lütfen hangi bilgiyi (örn: fatura tutarı) ve yeni değerini belirtin.";
    }

    final query = FirebaseFirestore.instance
        .collection('users').doc(widget.userId).collection('readings')
        .where('installationId', isEqualTo: installationId)
        .orderBy('readingTime', descending: true).limit(1);

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) {
      return "$installationId tesisat numarasına ait bir kayıt bulunamadı.";
    }
    final docToUpdate = snapshot.docs.first;

    if (!confirmed) {
      final currentData = docToUpdate.data();
      final summary = StringBuffer("$installationId tesisat numaralı kayıtta yapılacak değişiklikler:\n");
      fieldsToUpdate.forEach((key, value) {
        summary.writeln("- ${key.replaceAll('Amount', ' Tutarı').replaceAll('Value', ' Değeri')}: ${currentData[key]} -> $value");
      });
      summary.write("\nBu değişikliği onaylıyor musunuz?");
      return summary.toString();
    }

    try {
      // HATA ÇÖZÜMÜ: Firestore'a yazmadan önce tarih formatını dönüştür.
      final Map<String, dynamic> processedFields = Map.from(fieldsToUpdate);
      if (processedFields.containsKey('dueDate') && processedFields['dueDate'] is String) {
        try {
          final parsedDate = DateTime.parse(processedFields['dueDate']);
          processedFields['dueDate'] = Timestamp.fromDate(parsedDate);
        } catch (e) {
          return "Geçersiz tarih formatı. Lütfen YYYY-MM-DD formatında bir tarih girin.";
        }
      }

      await docToUpdate.reference.update(processedFields);
      return "$installationId tesisat numaralı kayıt başarıyla güncellendi.";
    } catch (e) {
      return "Kayıt güncellenirken bir hata oluştu: $e";
    }
  }

  /// Chatbot aracılığıyla yeni kayıt oluşturan ve onay isteyen fonksiyon.
  Future<String> _createNewReading({
    double? readingValue,
    double? invoiceAmount,
    String? unit,
    String? meterName,
    String? installationId,
    DateTime? dueDate,
    bool confirmed = false,
  }) async {
    if (installationId == null) {
      return "Harika, kayda başlayalım. Lütfen sayacın tesisat numarasını girin.";
    }
    if (readingValue == null) {
      return "Tesisat numarasını aldım. Şimdi de okuma değerini (tüketimi) girin lütfen.";
    }
    if (unit == null) {
      return "Anladım. Peki bu tüketim elektrik (kWh) mi yoksa su (m³) için mi?";
    }

    if (!confirmed) {
      final summary = StringBuffer("Aşağıdaki bilgileri kaydetmek üzereyim:\n");
      summary.writeln("- Tesisat No: $installationId");
      summary.writeln("- Okuma Değeri: $readingValue $unit");
      if (meterName != null) summary.writeln("- Sayaç Adı: $meterName");
      if (invoiceAmount != null) summary.writeln("- Fatura Tutarı: ₺${invoiceAmount.toStringAsFixed(2)}");
      if (dueDate != null) summary.writeln("- Son Ödeme Tarihi: ${DateFormat('dd MMMM yyyy', 'tr_TR').format(dueDate)}");
      summary.write("\nBu bilgileri onaylıyor musunuz?");
      return summary.toString();
    }

    try {
      final newReading = <String, dynamic>{
        'installationId': installationId,
        'readingValue': readingValue,
        'unit': unit,
        'readingTime': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (invoiceAmount != null) newReading['invoiceAmount'] = invoiceAmount;
      if (meterName != null) newReading['meterName'] = meterName;
      if (dueDate != null) newReading['dueDate'] = Timestamp.fromDate(dueDate);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('readings')
          .add(newReading);

      return "Harika! Yeni $unit kaydınız başarıyla oluşturuldu.";

    } catch (e) {
      return "Kayıt oluşturulurken bir hata oluştu: $e";
    }
  }

  /// Veri analiz fonksiyonu
  Future<String> _getConsumptionAnalysis({int? periodInMonths, String? dataType, String? analysisType}) async {
    try {
      if (periodInMonths == null || dataType == null || analysisType == null) {
        return "Analiz için zaman aralığı, veri türü (fatura/tuketim) ve analiz türü (ortalama/toplam/karsilastirma) gereklidir.";
      }
      final now = DateTime.now();
      final currentPeriodStart = DateTime(now.year, now.month - periodInMonths, 1);
      final query = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('readings')
          .where('readingTime', isGreaterThanOrEqualTo: Timestamp.fromDate(currentPeriodStart));

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return "Belirtilen dönem için veri bulunamadı.";
      double total = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (dataType == 'fatura' && data.containsKey('invoiceAmount')) {
          total += data['invoiceAmount'] ?? 0;
        } else if (dataType == 'tuketim' && data.containsKey('readingValue')) {
          total += data['readingValue'] ?? 0;
        }
      }
      if (analysisType == 'ortalama') {
        final average = total / snapshot.docs.length;
        return "Son $periodInMonths ay için ortalama $dataType: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(average)}";
      } else if (analysisType == 'toplam') {
        return "Son $periodInMonths ay için toplam $dataType: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(total)}";
      } else if (analysisType == 'karsilastirma') {
        final previousPeriodEnd = currentPeriodStart.subtract(const Duration(days: 1));
        final previousPeriodStart = DateTime(previousPeriodEnd.year, previousPeriodEnd.month - periodInMonths + 1, 1);
        final prevQuery = FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('readings')
            .where('readingTime', isGreaterThanOrEqualTo: Timestamp.fromDate(previousPeriodStart))
            .where('readingTime', isLessThanOrEqualTo: Timestamp.fromDate(previousPeriodEnd));
        final prevSnapshot = await prevQuery.get();
        if (prevSnapshot.docs.isEmpty) return "Karşılaştırma için önceki döneme ait veri bulunamadı.";
        double prevTotal = 0;
        for (var doc in prevSnapshot.docs) {
          final data = doc.data();
          if (dataType == 'fatura' && data.containsKey('invoiceAmount')) {
            prevTotal += data['invoiceAmount'] ?? 0;
          } else if (dataType == 'tuketim' && data.containsKey('readingValue')) {
            prevTotal += data['readingValue'] ?? 0;
          }
        }
        if (prevTotal == 0) return "Önceki dönemde veri olmadığı için karşılaştırma yapılamıyor.";
        final difference = total - prevTotal;
        final percentageChange = (difference / prevTotal * 100).toStringAsFixed(2);
        final formattedTotal = NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(total);
        final formattedPrevTotal = NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(prevTotal);
        String result = "Son $periodInMonths ayın toplamı ($formattedTotal), önceki döneme ($formattedPrevTotal) göre ";
        result += difference >= 0 ? "%$percentageChange artış gösterdi." : "%${percentageChange.replaceAll('-', '')} azalış gösterdi.";
        return result;
      }
      return "Geçersiz analiz türü.";
    } catch (e) {
      return "Analiz sırasında bir hata oluştu: $e";
    }
  }

  Future<Map<String, dynamic>> getGeminiResponse(List<Map<String, dynamic>> history) async {
    final apiKey = "";
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey');

    final systemPrompt = """
      Sen, 'AkışMetre' adlı bir mobil uygulama için uzman bir destek asistanısın. Adın 'Asistan'.
      Görevin, kullanıcıya yardımcı olmak. Bunu beş şekilde yaparsın:
      1. Uygulamanın nasıl kullanılacağını anlatırsın.
      2. Veri analizi yaparsın (`getConsumptionAnalysis` aracı).
      3. Yeni veri kaydı oluşturursun (`createNewReading` aracı).
      4. Mevcut kayıtları güncellersin (`updateReading` aracı).
      5. Mevcut kayıtları silersin (`deleteReading` aracı).

      **EN ÖNEMLİ KURAL:**
      - Bir işlem (silme, güncelleme, yeni kayıt) yapmadan önce **MUTLAKA** kullanıcıdan onay almalısın. İlgili fonksiyonu `confirmed: false` ile çağırarak bir özet oluştur ve kullanıcıya sun. Kullanıcı "evet", "onayla" derse, aynı fonksiyonu bu sefer `confirmed: true` ile çağırarak işlemi tamamla.
      - **ASLA** kullanıcıya teknik fonksiyon adlarından bahsetme.

      **ARAÇLARIN (FONKSİYONLARIN):**

      **1. Veri Girişi (createNewReading):**
         - Kullanıcı 'kaydet', 'ekle' gibi bir istekte bulunduğunda, zorunlu olan `installationId` ve `readingValue` bilgilerini topla ve onay akışını başlat.

      **2. Veri Güncelleme (updateReading):**
         - Kullanıcı 'güncelle', 'değiştir' gibi bir istekte bulunduğunda, hangi kaydı (`installationId`) ve hangi bilgileri (`fieldsToUpdate`) değiştirmek istediğini öğren ve onay akışını başlat.

      **3. Veri Silme (deleteReading):**
         - Kullanıcı 'sil', 'kaldır' gibi bir istekte bulunduğunda, hangi kaydı (`installationId`) silmek istediğini öğren ve onay akışını başlat.
         
         **4. Şifre değiştirme işlemi:**
         - Kullanıcı şifresini değiştirmek için altta bulunan profil sekmesine gitmeli ve şifremi değiştir butonuna tıklayarak mailine şifre değiştirme maili gelecektir linki takip ederek şifresini değiştirebilir.
         
         **5. Yeni fatura verisi eklemek :**
         - Kullanıcı yeni bir fatura bilgisi ekleyebilmek için alt sekmede bulunan + işaretine yani ekle butonuna bastıktan sonra ister manuel şekilde veri ekleyebilir isterse sağ üstte bulunan kamera görseline tıklayarak faturanın görselini taratarak bilgilerin otomatik olarak çekilmesini sağlayabilir ardından gerekli bilgiler doldurulduktan sonra altta bulunan kaydet butonuna tıklarsa yeni fatura bilgisi kayıtedilir.
         
         **6. Hesabp silimi:**
         - Kullanıcı hesabını silmek için profil kısmına gitmeli ardından tehlikeli alandan hesabımı sil butonuna tıklayıp onay verdikten sonra hesap silinir ayrıca kullanıcı içindeki tüm veriler de kaybedilir.
         
         **7. Fatura detayları:**
         - Kullanıcı girdiği fatura detaylarını görmek isterse alt sekmede bulunan geçmiş butonuna tıklayarak girdiği faturaları görüntüleyebilir ayrıca fatura detaylarını güncelleyebilir ya da kalıcı olarak silebilir.
         
         **8. Fatura detayları:**
         - Kullanıcı faturalara dair görsel bir bilgi elde etmek isterse alt sekmede bulunan grafik sekmesinden 3 ayrı grafiğe ulaşablir burada aylık olarak fatura tutarlarını tüketim miktarlarına dair bilgiyi ve girdiği faturalaın kategorik olarak sınıflandırmasını görebilir.
         
         
    """;

    final body = {
      'contents': history,
      'systemInstruction': {
        'parts': [{'text': systemPrompt}]
      },
      'tools': [{
        'functionDeclarations': [
          {
            'name': 'getConsumptionAnalysis',
            'description': 'Kullanıcının belirli bir dönemdeki verilerini analiz eder.',
            'parameters': { 'type': 'OBJECT', 'properties': { 'periodInMonths': {'type': 'INTEGER'}, 'dataType': {'type': 'STRING'}, 'analysisType': {'type': 'STRING'} }, 'required': ['periodInMonths', 'dataType', 'analysisType'] }
          },
          {
            'name': 'createNewReading',
            'description': 'Kullanıcı için yeni bir sayaç okuma kaydı oluşturur.',
            'parameters': { 'type': 'OBJECT', 'properties': { 'readingValue': {'type': 'NUMBER'}, 'invoiceAmount': {'type': 'NUMBER'}, 'unit': {'type': 'STRING'}, 'meterName': {'type': 'STRING'}, 'installationId': {'type': 'STRING'}, 'dueDate': {'type': 'STRING', 'description': "YYYY-MM-DD formatında tarih."}, 'confirmed': {'type': 'BOOLEAN'} }, 'required': ['installationId', 'readingValue', 'unit'] }
          },
          {
            'name': 'deleteReading',
            'description': 'Belirtilen tesisat numarasına ait en son kaydı siler.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'installationId': {'type': 'STRING', 'description': 'Silinecek kaydın tesisat numarası.'},
                'confirmed': {'type': 'BOOLEAN', 'description': 'Kullanıcı silme işlemini onayladıysa true olur.'}
              },
              'required': ['installationId']
            }
          },
          {
            'name': 'updateReading',
            'description': 'Belirtilen tesisat numarasına ait en son kaydı günceller.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'installationId': {'type': 'STRING', 'description': 'Güncellenecek kaydın tesisat numarası.'},
                'fieldsToUpdate': {'type': 'OBJECT', 'description': 'Güncellenecek alanları ve yeni değerlerini içeren bir nesne. Örn: {"invoiceAmount": 350, "readingValue": 200}'},
                'confirmed': {'type': 'BOOLEAN', 'description': 'Kullanıcı güncelleme işlemini onayladıysa true olur.'}
              },
              'required': ['installationId', 'fieldsToUpdate']
            }
          }
        ]
      }],
      'generationConfig': { 'temperature': 0.2, 'topP': 0.8, 'topK': 40, 'maxOutputTokens': 2048 }
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        final candidate = data['candidates'][0];
        if (candidate['content'] != null && candidate['content']['parts'] != null) {
          final parts = candidate['content']['parts'];
          if (parts.isNotEmpty) {
            return parts[0] as Map<String, dynamic>;
          }
        }
      }
      throw Exception("API yanıtı beklenen formatta değil: ${jsonEncode(data)}");
    } else {
      print('Hata kodu: ${response.statusCode}');
      print('Hata mesajı: ${response.body}');
      throw Exception("API ile iletişim kurarken bir sorun oluştu. (Hata Kodu: ${response.statusCode})");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Destek Asistanı"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Geçmişi Sil',
            onPressed: _isHistoryLoading || _isLoading ? null : _clearHistory,
          ),
        ],
      ),
      body: _isHistoryLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: LinearProgressIndicator(),
            ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
        decoration: BoxDecoration(
          color: message.isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Mesajınızı yazın...',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30.0),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onSubmitted: (value) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _isLoading ? null : _sendMessage,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
