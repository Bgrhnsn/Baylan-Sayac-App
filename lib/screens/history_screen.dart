import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:sayacfaturapp/screens/reading_detail_screen.dart';
// GÜNCELLEME: Stil sahibi özel kartımızı import ediyoruz.
import 'package:sayacfaturapp/theme/custom_components.dart';

/// Tüm sayaç okumalarını listeleyen ve filtreleme özellikleri sunan ekran.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';//aranan metiin
  String? _selectedUnit;//kwh m3 hepsi
  DateTimeRange? _selectedDateRange;//tarih filtreleme

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // GÜNCELLEME: Tema verilerini en üste alıyoruz.
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(_currentUser?.uid)
                .collection('readings')
                .orderBy('readingTime', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  // GÜNCELLEME: Metin stili temadan alınıyor.
                  child: Text(
                    'Henüz hiç kayıt bulunmuyor.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
                  ),
                );
              }

              var allReadings = snapshot.data!.docs
                  .map((doc) => MeterReading.fromSnapshot(doc))
                  .toList();

              final filteredReadings = allReadings.where((reading) {
                final searchMatch = _searchQuery.isEmpty ||
                    (reading.meterName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
                    reading.installationId.toLowerCase().contains(_searchQuery.toLowerCase());
                final unitMatch = _selectedUnit == null || reading.unit == _selectedUnit;
                final dateMatch = _selectedDateRange == null ||
                    (reading.readingTime.isAfter(_selectedDateRange!.start) &&
                        reading.readingTime.isBefore(_selectedDateRange!.end.add(const Duration(days: 1))));
                return searchMatch && unitMatch && dateMatch;
              }).toList();

              if (filteredReadings.isEmpty) {
                return Center(
                  // GÜNCELLEME: Metin stili temadan alınıyor.
                  child: Text(
                    'Bu filtrelere uygun kayıt bulunamadı.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                itemCount: filteredReadings.length,
                itemBuilder: (context, index) {
                  return _buildReadingListItem(context, filteredReadings[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Sayaç Adı veya Tesisat No ile Ara',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                },
              )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Çipler artık kendi Row'u içinde ve sadece gerektiğ/i kadar yer kaplıyor.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _selectedUnit == null,
                    onSelected: (selected) => setState(() => _selectedUnit = null),
                    showCheckmark: false,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('kWh'),
                    avatar: Icon(Icons.electric_bolt, size: 18, color: _selectedUnit == 'kWh' ? Colors.white : theme.colorScheme.primary),
                    selected: _selectedUnit == 'kWh',
                    onSelected: (selected) => setState(() => _selectedUnit = 'kWh'),
                    showCheckmark: false,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('m³'),
                    avatar: Icon(Icons.water_drop, size: 18, color: _selectedUnit == 'm³' ? Colors.white : Colors.blueAccent),
                    selected: _selectedUnit == 'm³',
                    onSelected: (selected) => setState(() => _selectedUnit = 'm³'),
                    showCheckmark: false,
                  ),
                ],
              ),
              // Spacer, kalan tüm boşluğu doldurarak butonları sağa iter.
              const Spacer(),
              IconButton(
                icon: Icon(Icons.calendar_month, color: _selectedDateRange != null ? theme.colorScheme.primary : Colors.grey),
                tooltip: 'Tarihe Göre Filtrele',
                onPressed: _selectDateRange,
              ),
              Opacity(
                opacity: _selectedDateRange != null ? 1.0 : 0.0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  tooltip: 'Tarih Filtresini Temizle',
                  onPressed: _selectedDateRange != null
                      ? () => setState(() => _selectedDateRange = null)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadingListItem(BuildContext context, MeterReading reading) {
    final theme = Theme.of(context);
    final IconData iconData;
    final Color iconColor;
    if (reading.unit == 'kWh') {
      iconData = Icons.electric_bolt;
      iconColor = Colors.orangeAccent;
    } else if (reading.unit == 'm³') {
      iconData = Icons.water_drop;
      iconColor = Colors.blueAccent;
    } else {
      iconData = Icons.help_outline;
      iconColor = Colors.grey;
    }

    // GÜNCELLEME: Hard-coded Card yerine merkezi AppStyledCard kullanılıyor.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: AppStyledCard(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: iconColor.withOpacity(0.15),
            child: Icon(iconData, color: iconColor),
          ),
          title: Text(
            reading.meterName ?? reading.installationId,
            style: theme.textTheme.titleMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Satır: Orijinal subtitle metni
              Text(
                '${reading.readingValue} ${reading.unit ?? ''} | ${DateFormat('dd MMM yyyy', 'tr_TR').format(reading.readingTime)}',
                style: theme.textTheme.bodyMedium,
              ),

              // GÜNCELLEME: Fatura tutarı Chip'i buradan kaldırıldı.
              // Row widget'ı artık sadece fatura ikonu için gerekli.
              if (reading.invoiceImageUrl != null) ...[
                const SizedBox(height: 8), // Metin ile Chip arasına boşluk
                Chip(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.secondaryContainer.withOpacity(0.6),
                  avatar: Icon(
                    Icons.receipt_long_outlined,
                    size: 14,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  label: Text(
                    'Fatura',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),

          // YENİ: trailing alanı fatura tutarını göstermek için eklendi.
          trailing: reading.invoiceAmount != null
              ? Text(
            NumberFormat.currency(locale: 'tr_TR', symbol: '₺')
                .format(reading.invoiceAmount!),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          )
              : null,

          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => ReadingDetailScreen(reading: reading),
            ));
          },
        ),
      ),
    );
  }
}