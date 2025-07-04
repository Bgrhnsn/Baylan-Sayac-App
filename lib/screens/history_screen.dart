import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:sayacfaturapp/screens/reading_detail_screen.dart';

/// Tüm sayaç okumalarını listeleyen ve filtreleme özellikleri sunan ekran.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController _searchController = TextEditingController();

  // Filtreleme için state değişkenleri
  String _searchQuery = '';
  String? _selectedUnit; // null: Tümü, 'kWh': Elektrik, 'm³': Su
  DateTimeRange? _selectedDateRange;

  // DÜZELTME: Arama dinleyicisi initState'ten kaldırıldı.
  // Bunun yerine TextField'ın onChanged özelliği kullanılacak.
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Tarih aralığı seçiciyi açan metod
  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtreleme ve arama çubuğu
        _buildFilterBar(),
        // Filtrelenmiş listeyi gösteren StreamBuilder
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
                return const Center(
                  child: Text(
                    'Henüz hiç kayıt bulunmuyor.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }

              var allReadings = snapshot.data!.docs
                  .map((doc) => MeterReading.fromSnapshot(doc))
                  .toList();

              // Filtreleri uygula
              final filteredReadings = allReadings.where((reading) {
                final searchMatch = _searchQuery.isEmpty ||
                    reading.installationId.toLowerCase().contains(_searchQuery.toLowerCase());
                final unitMatch = _selectedUnit == null || reading.unit == _selectedUnit;
                final dateMatch = _selectedDateRange == null ||
                    (reading.readingTime.isAfter(_selectedDateRange!.start) &&
                        reading.readingTime.isBefore(_selectedDateRange!.end.add(const Duration(days: 1))));

                return searchMatch && unitMatch && dateMatch;
              }).toList();

              if (filteredReadings.isEmpty) {
                return const Center(
                  child: Text(
                    'Bu filtrelere uygun kayıt bulunamadı.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(8.0),
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

  /// Filtreleme seçeneklerini içeren arayüzü oluşturan widget.
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Arama Çubuğu
          TextField(
            controller: _searchController,
            // DÜZELTME: Arama kutusundaki her değişiklikte state'i güncelleyen onChanged eklendi.
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              labelText: 'Tesisat No ile Ara',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  // Temizle butonuna basınca da state'i güncelle
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          // Birim ve Tarih Filtreleri
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8.0,
                  children: [
                    ChoiceChip(
                      label: const Text('Tümü'),
                      selected: _selectedUnit == null,
                      onSelected: (selected) {
                        setState(() => _selectedUnit = null);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('kWh'),
                      avatar: const Icon(Icons.electric_bolt, size: 16),
                      selected: _selectedUnit == 'kWh',
                      onSelected: (selected) {
                        setState(() => _selectedUnit = 'kWh');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('m³'),
                      avatar: const Icon(Icons.water_drop, size: 16),
                      selected: _selectedUnit == 'm³',
                      onSelected: (selected) {
                        setState(() => _selectedUnit = 'm³');
                      },
                    ),
                  ],
                ),
              ),
              // Tarih Filtresi Butonu
              IconButton(
                icon: Icon(Icons.calendar_month, color: _selectedDateRange != null ? Theme.of(context).primaryColor : Colors.grey),
                tooltip: 'Tarihe Göre Filtrele',
                onPressed: _selectDateRange,
              ),
              // Filtreleri Temizle Butonu
              if (_selectedDateRange != null)
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, color: Colors.grey),
                  tooltip: 'Tarih Filtresini Temizle',
                  onPressed: () => setState(() => _selectedDateRange = null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Liste elemanını oluşturan yardımcı metod.
  Widget _buildReadingListItem(BuildContext context, MeterReading reading) {
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.15),
          child: Icon(iconData, color: iconColor),
        ),
        title: Text(
          reading.installationId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${reading.readingValue} ${reading.unit ?? ''}\n'
              '${DateFormat('dd MMM, HH:mm', 'tr_TR').format(reading.readingTime)}',
        ),
        trailing: reading.invoiceAmount != null
            ? Text(
          NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(reading.invoiceAmount),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
        )
            : null,
        isThreeLine: true,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ReadingDetailScreen(reading: reading),
          ));
        },
      ),
    );
  }
}
