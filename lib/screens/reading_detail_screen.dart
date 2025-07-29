import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Düzenleme ekranını import ediyoruz.
import 'package:sayacfaturapp/screens/new_reading_screen.dart';

/// Bir sayaç okumasının tüm detaylarını gösteren, düzenleme ve silme
/// işlemlerine olanak tanıyan ekran.
class ReadingDetailScreen extends StatelessWidget {
  const ReadingDetailScreen({super.key, required this.reading});

  final MeterReading reading;

  // Silme işlemi için onay dialogu gösteren metod
  Future<void> _showDeleteConfirmation(BuildContext context) async {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Kaydı Sil'),
          content: const Text('Bu okuma kaydını silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              child: const Text('İptal'),
              onPressed: () {
                Navigator.of(ctx).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sil'),
              onPressed: () async {
                Navigator.of(ctx).pop(); // Dialogu kapat
                await _deleteReading(context);
              },
            ),
          ],
        );
      },
    );
  }

  // Firestore'dan kaydı silen metod
  Future<void> _deleteReading(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // GÜNCELLEME: Eğer bir görsel varsa, onu da Storage'dan siliyoruz.
      if (reading.invoiceImageUrl != null) {
        // Tam URL'den referansı alarak silme işlemi
        FirebaseStorage.instance.refFromURL(reading.invoiceImageUrl!).delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('readings')
          .doc(reading.id) // Silinecek dokümanın ID'si
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt başarıyla silindi.')),
        );
        Navigator.of(context).pop(); // Detay sayfasını kapat
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: Kayıt silinemedi. $e')),
        );
      }
    }
  }

  // GÜNCELLEME: Harita uygulamasını doğru URL ile açan metod.
  Future<void> _openMap(BuildContext context, double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harita uygulaması açılamadı.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(reading.meterName ?? reading.installationId),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Düzenle',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => NewReadingScreen(readingToEdit: reading),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Sil',
            onPressed: () => _showDeleteConfirmation(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // YENİ: Fatura görselini gösteren kart eklendi.
          if (reading.invoiceImageUrl != null)
            _buildInvoiceImageCard(context),

          _buildDetailCard(
            context,
            title: 'Tesisat Bilgileri',
            children: [
              if (reading.meterName != null && reading.meterName!.isNotEmpty)
                _DetailRow(
                  icon: Icons.label_important_outline,
                  label: 'Sayaç Adı',
                  value: reading.meterName!,
                ),
              _DetailRow(
                icon: Icons.confirmation_number_outlined,
                label: 'Tesisat Numarası',
                value: reading.installationId,
              ),
              _DetailRow(
                icon: reading.unit == 'kWh' ? Icons.electric_bolt : Icons.water_drop,
                label: 'Okuma Değeri',
                value: '${reading.readingValue} ${reading.unit ?? ''}',
              ),
              _DetailRow(
                icon: Icons.today,
                label: 'Okuma Zamanı',
                value: DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR').format(reading.readingTime),
              ),
            ],
          ),
          if (reading.invoiceAmount != null || reading.dueDate != null)
            _buildDetailCard(
              context,
              title: 'Fatura Bilgileri',
              children: [
                if (reading.invoiceAmount != null)
                  _DetailRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'Fatura Tutarı',
                    value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(reading.invoiceAmount!),
                  ),
                if (reading.dueDate != null)
                  _DetailRow(
                    icon: Icons.event_busy,
                    label: 'Son Ödeme Tarihi',
                    value: DateFormat('dd MMMM yyyy', 'tr_TR').format(reading.dueDate!),
                  ),
              ],
            ),
          if (reading.locationText != null || reading.gpsLat != null)
            _buildDetailCard(
              context,
              title: 'Konum Bilgileri',
              children: [
                if (reading.locationText != null && reading.locationText!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.map_outlined,
                    label: 'Adres Açıklaması',
                    value: reading.locationText!,
                  ),
                if (reading.gpsLat != null && reading.gpsLng != null) ...[
                  const SizedBox(height: 8),
                  // GÜNCELLEME: Harita görüntüsü için not eklendi.
                  // Static Map'in çalışması için Google Cloud'dan "Maps Static API"
                  // anahtarı alıp 'YOUR_API_KEY' kısmına yapıştırmalısınız.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(
                      onTap: () => _openMap(context, reading.gpsLat!, reading.gpsLng!),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.network(
                            'https://maps.googleapis.com/maps/api/staticmap?center=${reading.gpsLat},${reading.gpsLng}&zoom=15&size=600x300&markers=color:blue%7C${reading.gpsLat},${reading.gpsLng}&key=YOUR_API_KEY', // BURAYA KENDİ API KEY'İNİZİ GİRİN
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 150,
                                color: Colors.grey[300],
                                child: const Center(child: CircularProgressIndicator()),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 150,
                              color: Colors.grey[300],
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'Harita yüklenemedi.\n(API Anahtarı gerekli)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Haritada Gör', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  )
                ]
              ],
            ),
        ],
      ),
    );
  }

  // YENİ: Fatura görseli kartını oluşturan yardımcı widget.
  Widget _buildInvoiceImageCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias, // Görselin kartın köşelerine taşmasını engeller
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Fatura Görseli", style: Theme.of(context).textTheme.titleLarge),
          ),
          Image.network(
            reading.invoiceImageUrl!,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text("Görsel yüklenemedi.")),
              );
            },
          ),
        ],
      ),
    );
  }

  // Detay kartlarını oluşturan yardımcı widget
  Widget _buildDetailCard(BuildContext context, {required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

// Detay satırlarını oluşturan yardımcı widget
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}