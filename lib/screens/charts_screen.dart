import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

// Grafik verilerini ve etiketlerini bir arada tutmak için yardımcı sınıf.
class ChartDataPoint {
  final String label; // Örn: 'Oca', 'Şub'
  final double value;
  final DateTime date; // Karşılaştırma için tarihi de tutalım

  ChartDataPoint({required this.label, required this.value, required this.date});
}

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // --- GÜNCELLENMİŞ STATE YÖNETİMİ ---
  int _selectedChartType = 0; // 0: Tutar, 1: Tüketim, 2: Dağılım
  String? _selectedMeterId;
  int _selectedQuickFilter = 1; // 0: Son 3 Ay, 1: Son 6 Ay, 2: Bu Yıl
  int selectedConsumptionType = 0; // 0: Elektrik, 1: Su

  Stream<QuerySnapshot>? _chartStream;
  Future<Map<String, String>>? _uniqueMetersFuture;

  // YENİ: Son başarılı veri kümesini tutarak "ekran flaşlamasını" önleyen önbellek.
  List<MeterReading>? _cachedReadings;

  @override
  void initState() {
    super.initState();
    _uniqueMetersFuture = _fetchUniqueMeters();
    _applyQuickFilter(1);
  }

  Future<Map<String, String>> _fetchUniqueMeters() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser?.uid)
        .collection('readings')
        .get();

    final uniqueMeters = <String, String>{};
    if (snapshot.docs.isNotEmpty) {
      final allReadings = snapshot.docs.map((doc) => MeterReading.fromSnapshot(doc)).toList();
      for (var reading in allReadings) {
        uniqueMeters[reading.installationId] = reading.meterName ?? reading.installationId;
      }
    }
    return uniqueMeters;
  }

  void _updateStream() {
    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser?.uid)
        .collection('readings');

    final now = DateTime.now();
    DateTimeRange dateRange;
    switch (_selectedQuickFilter) {
      case 0:
        dateRange = DateTimeRange(start: DateTime(now.year, now.month - 2, 1), end: now);
        break;
      case 2:
        dateRange = DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
        break;
      default:
        dateRange = DateTimeRange(start: DateTime(now.year, now.month - 5, 1), end: now);
        break;
    }
    query = query
        .where('readingTime', isGreaterThanOrEqualTo: dateRange.start)
        .where('readingTime', isLessThanOrEqualTo: dateRange.end);

    if (_selectedMeterId != null) {
      query = query.where('installationId', isEqualTo: _selectedMeterId);
    }

    query = query.orderBy('readingTime', descending: true);

    setState(() {
      _chartStream = query.snapshots();
    });
  }

  Map<String, dynamic> _processReadings(List<MeterReading> readings) {
    final Map<String, double> monthlyInvoiceTotals = {};
    final Map<String, double> monthlyConsumptionTotalsByUnit = {};
    final Map<String, double> distributionTotals = {'kWh': 0.0, 'm³': 0.0};
    final Map<String, DateTime> monthDates = {};

    for (var reading in readings) {
      final monthKey = DateFormat('yyyy-MM').format(reading.readingTime);
      monthDates.putIfAbsent(monthKey, () => reading.readingTime);

      if (reading.invoiceAmount != null && reading.invoiceAmount! > 0) {
        monthlyInvoiceTotals.update(monthKey, (value) => value + reading.invoiceAmount!, ifAbsent: () => reading.invoiceAmount!);
        if (reading.unit != null) {
          distributionTotals.update(reading.unit!, (value) => value + reading.invoiceAmount!, ifAbsent: () => reading.invoiceAmount!);
        }
      }
      if (reading.readingValue > 0 && reading.unit != null) {
        final key = '$monthKey-${reading.unit}';
        monthlyConsumptionTotalsByUnit.update(key, (value) => value + reading.readingValue, ifAbsent: () => reading.readingValue);
      }
    }

    final invoiceData = monthlyInvoiceTotals.entries.map((e) {
      final date = monthDates[e.key]!;
      return ChartDataPoint(label: DateFormat('MMM', 'tr_TR').format(date), value: e.value, date: date);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return {
      'invoice': invoiceData,
      'consumption': monthlyConsumptionTotalsByUnit,
      'distribution': distributionTotals,
    };
  }

  void _applyQuickFilter(int index) {
    setState(() {
      _selectedQuickFilter = index;
    });
    _updateStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: FutureBuilder<Map<String, String>>(
        future: _uniqueMetersFuture,
        builder: (context, metersSnapshot) {
          if (!metersSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (metersSnapshot.hasError) {
            return Center(child: Text('Filtreler yüklenemedi: ${metersSnapshot.error}'));
          }

          final uniqueMeters = metersSnapshot.data ?? {};

          return StreamBuilder<QuerySnapshot>(
            stream: _chartStream,
            builder: (context, chartSnapshot) {
              // --- YENİ AKICI FİLTRELEME MANTIĞI ---

              // 1. Veri geldiyse, önbelleği güncelle.
              if (chartSnapshot.hasData) {
                _cachedReadings = chartSnapshot.data!.docs.map((doc) => MeterReading.fromSnapshot(doc)).toList();
              }

              // 2. Hata varsa göster.
              if (chartSnapshot.hasError) {
                return Center(child: Text('Veri yüklenemedi: ${chartSnapshot.error}'));
              }

              // 3. Önbellek tamamen boşsa (ilk yükleme anı), ana yükleme animasyonunu göster.
              if (_cachedReadings == null) {
                return const Center(child: CircularProgressIndicator());
              }

              // 4. Önbellekte veri var, arayüzü bu veriyle oluştur.
              final filteredReadings = _cachedReadings!;
              final processedData = _processReadings(filteredReadings);
              final invoiceData = processedData['invoice'] as List<ChartDataPoint>;
              final consumptionData = processedData['consumption'] as Map<String, double>;
              final distributionData = processedData['distribution'] as Map<String, double>;

              // 5. Ana arayüzü bir Stack içine alarak yükleme animasyonunu üst katmana ekle.
              return Stack(
                children: [
                  // Her zaman görünen ana içerik
                  ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      _buildFilterBar(context, uniqueMeters),
                      const SizedBox(height: 24),

                      // Filtrelenmiş veri boşsa, özet ve grafikler yerine mesaj göster.
                      if(filteredReadings.isEmpty)
                        const Center(heightFactor: 5, child: Text('Bu filtreler için gösterilecek veri bulunamadı.', style: TextStyle(fontSize: 16, color: Colors.grey)))
                      else
                        Column(
                          children: [
                            _buildSummaryCards(filteredReadings, invoiceData, consumptionData),
                            const SizedBox(height: 24),
                            SegmentedButton<int>(
                              style: SegmentedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF86868B), selectedForegroundColor: const Color(0xFF007AFF), selectedBackgroundColor: const Color(0xFFE5E5EA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              segments: const [
                                ButtonSegment(value: 0, label: Text('Tutar'), icon: Icon(Icons.show_chart)),
                                ButtonSegment(value: 1, label: Text('Tüketim'), icon: Icon(Icons.speed)),
                                ButtonSegment(value: 2, label: Text('Dağılım'), icon: Icon(Icons.pie_chart)),
                              ],
                              selected: {_selectedChartType},
                              onSelectionChanged: (newSelection) => setState(() => _selectedChartType = newSelection.first),
                            ),
                            const SizedBox(height: 24),
                            if (_selectedChartType == 0)
                              _buildMonthlyChart(invoiceData)
                            else if (_selectedChartType == 1)
                              _buildConsumptionChart(consumptionData)
                            else
                              _buildCategoryChart(distributionData),
                          ],
                        )
                    ],
                  ),

                  // Filtreleme sırasında üstte görünecek yarı şeffaf yükleme animasyonu.
                  if (chartSnapshot.connectionState == ConnectionState.waiting)
                    Container(
                      color: const Color(0xFFF5F5F7).withOpacity(0.7),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // --- FİLTRELEME VE ÖZET KARTLARI ---

  Widget _buildFilterBar(BuildContext context, Map<String, String> uniqueMeters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Filtreler', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFF1D1D1F))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedMeterId,
          hint: const Text('Tüm Sayaçlar'),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.filter_list, color: Color(0xFF86868B)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Tüm Sayaçlar')),
            ...uniqueMeters.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(entry.value))),
          ],
          onChanged: (value) {
            setState(() => _selectedMeterId = value);
            _updateStream();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildQuickFilterChip('Son 3 Ay', 0)),
            const SizedBox(width: 8),
            Expanded(child: _buildQuickFilterChip('Son 6 Ay', 1)),
            const SizedBox(width: 8),
            Expanded(child: _buildQuickFilterChip('Bu Yıl', 2)),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickFilterChip(String label, int index) {
    final isSelected = _selectedQuickFilter == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) => _applyQuickFilter(index),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE5E5EA),
      labelStyle: TextStyle(fontWeight: FontWeight.w500, color: isSelected ? const Color(0xFF007AFF) : const Color(0xFF86868B)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
      showCheckmark: false,
    );
  }

  Widget _buildSummaryCards(List<MeterReading> readings, List<ChartDataPoint> invoiceData, Map<String, double> consumptionData) {
    if (readings.isEmpty) return const SizedBox.shrink();

    final totalInvoice = readings.fold(0.0, (sum, item) => sum + (item.invoiceAmount ?? 0));
    final averageInvoice = invoiceData.isNotEmpty ? invoiceData.map((e) => e.value).reduce((a, b) => a + b) / invoiceData.length : 0.0;

    final monthlyConsumptionTotals = <String, double>{};
    consumptionData.forEach((key, value) {
      final monthKey = key.substring(0, 7);
      monthlyConsumptionTotals.update(monthKey, (v) => v + value, ifAbsent: () => value);
    });

    String maxConsumptionText = 'Veri Yok';
    if(monthlyConsumptionTotals.isNotEmpty) {
      final maxEntry = monthlyConsumptionTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
      final monthLabel = DateFormat('MMM', 'tr_TR').format(DateFormat('yyyy-MM').parse(maxEntry.key));
      maxConsumptionText = '${maxEntry.value.toStringAsFixed(0)} kWh/m³ ($monthLabel)';
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(title: 'Dönem Toplamı', value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(totalInvoice), icon: Icons.functions, color: const Color(0xFF007AFF))),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Aylık Ortalama', value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(averageInvoice), icon: Icons.show_chart, color: const Color(0xFF30D158))),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(title: 'Rekor Tüketim', value: maxConsumptionText, icon: Icons.trending_up, color: const Color(0xFFFF3B30)),
      ],
    );
  }

  // --- GRAFİK OLUŞTURMA METOTLARI (İÇERİKLERİ AYNI KALIYOR)---

  Widget _buildMonthlyChart(List<ChartDataPoint> data) {
    if (data.length < 2) {
      return _buildChartCard(
          title: 'Aylık Fatura Tutarı',
          period: 'Yeterli Veri Yok',
          child: const SizedBox(height: 200, child: Center(child: Text('Karşılaştırma için en az 2 aylık veri gerekli.'))));
    }

    final currentAmount = data.last.value;
    final previousAmount = data[data.length - 2].value;
    final change = currentAmount - previousAmount;

    final minY = (data.map((d) => d.value).reduce(min) * 0.9).floorToDouble();
    final maxY = (data.map((d) => d.value).reduce(max) * 1.1).ceilToDouble();
    final interval = ((maxY - minY) / 4).roundToDouble();

    return _buildChartCard(
      title: 'Aylık Fatura Tutarı',
      period: DateFormat('yyyy').format(data.last.date),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval > 0 ? interval : 100, getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFF2F2F7), strokeWidth: 1, dashArray: [5, 5])),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        if (value.toInt() < data.length) return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(data[value.toInt()].label, style: const TextStyle(color: Color(0xFF86868B), fontWeight: FontWeight.w500, fontSize: 12)));
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: interval > 0 ? interval : 100,
                      getTitlesWidget: (double value, TitleMeta meta) => Text('₺${(value / 1000).toStringAsFixed(1)}k', style: const TextStyle(color: Color(0xFF86868B), fontWeight: FontWeight.w500, fontSize: 12)),
                      reservedSize: 42,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: data.length - 1.toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: data.asMap().entries.map((entry) => FlSpot(entry.key.toDouble(), entry.value.value)).toList(),
                    isCurved: true,
                    gradient: const LinearGradient(colors: [Color(0xFF007AFF), Color(0xFF007AFF)]),//grafik çizgileri ve noktalarının rengi
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: const Color(0xFF007AFF), strokeWidth: 3, strokeColor: Colors.white)),
                    belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [const Color(0xFF007AFF).withOpacity(0.1), const Color(0xFF007AFF).withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildStatsRow([
            _StatItem(value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0).format(currentAmount), label: 'Bu Ay', color: change > 0 ? const Color(0xFFFF3B30) : const Color(0xFF30D158)),
            _StatItem(value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0).format(previousAmount), label: 'Geçen Ay', color: const Color(0xFF86868B)),
            _StatItem(value: '${change > 0 ? '+' : ''}${NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0).format(change)}', label: 'Değişim', color: change > 0 ? const Color(0xFFFF3B30) : const Color(0xFF30D158)),
          ]),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(Map<String, double> data) {
    final totalAmount = data.values.fold(0.0, (sum, item) => sum + item);
    if (totalAmount == 0) {
      return _buildChartCard(
          title: 'Fatura Kategorileri',
          period: 'Veri Yok',
          child: const SizedBox(height: 200, child: Center(child: Text('Dağılım için fatura verisi gerekli.'))));
    }

    final categoryData = [
      if(data['kWh']! > 0) CategoryData(name: 'Elektrik', amount: data['kWh']!, color: const Color(0xFFFFC300)),
      if(data['m³']! > 0) CategoryData(name: 'Su', amount: data['m³']!, color: const Color(0xFF007AFF)),
    ];

    return _buildChartCard(
      title: 'Fatura Kategorileri',
      period: DateFormat('MMMM', 'tr_TR').format(DateTime.now()),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(touchCallback: (FlTouchEvent event, pieTouchResponse) {}),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: categoryData.map((data) {
                  final percentage = (data.amount / totalAmount * 100).round();
                  return PieChartSectionData(
                    color: data.color,
                    value: data.amount,
                    title: '$percentage%',
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLegend(categoryData),
        ],
      ),
    );
  }

  Widget _buildConsumptionChart(Map<String, double> data) {
    final now = DateTime.now();
    final currentMonthKeyKwh = '${DateFormat('yyyy-MM').format(now)}-kWh';
    final currentMonthKeyM3 = '${DateFormat('yyyy-MM').format(now)}-m³';
    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final prevMonthKeyKwh = '${DateFormat('yyyy-MM').format(prevMonth)}-kWh';
    final prevMonthKeyM3 = '${DateFormat('yyyy-MM').format(prevMonth)}-m³';

    final consumptionDataList = [
      ConsumptionData(currentUsage: data[currentMonthKeyKwh] ?? 0, previousUsage: data[prevMonthKeyKwh] ?? 0, limit: 450, unit: 'kWh', type: 'Elektrik'),
      ConsumptionData(currentUsage: data[currentMonthKeyM3] ?? 0, previousUsage: data[prevMonthKeyM3] ?? 0, limit: 120, unit: 'm³', type: 'Su'),
    ];

    final selectedData = consumptionDataList[selectedConsumptionType];

    return _buildChartCard(
      title: 'Tüketim Oranı',
      period: DateFormat('MMMM', 'tr_TR').format(DateTime.now()),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(child: _buildTab('Elektrik', 0)),
                Expanded(child: _buildTab('Su', 1)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 120,
            width: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: selectedData.limit > 0 ? selectedData.percentage / 100 : 0,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: const Color(0xFFE5E5EA),
                  valueColor: AlwaysStoppedAnimation<Color>(selectedConsumptionType == 0 ? const Color(0xFF007AFF) : const Color(0xFF30D158)),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(selectedData.currentUsage.toInt().toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1D1D1F))),
                      Text(selectedData.unit, style: const TextStyle(fontSize: 12, color: Color(0xFF86868B))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildStatsRow([
            _StatItem(value: '${selectedData.currentUsage.toInt()}', label: 'Bu Ay (${selectedData.unit})', color: const Color(0xFF1D1D1F)),
            _StatItem(value: '${selectedData.previousUsage.toInt()}', label: 'Geçen Ay', color: const Color(0xFF86868B)),
            _StatItem(value: '${selectedData.limit.toInt()}', label: 'Limit', color: const Color(0xFF86868B)),
          ]),
        ],
      ),
    );
  }

  // --- YARDIMCI WIDGET'LAR ---

  Widget _buildChartCard({required String title, required String period, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFE5E5EA).withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1D1D1F))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(20)),
                  child: Text(period, style: const TextStyle(fontSize: 14, color: Color(0xFF86868B))),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, int index) {
    final isSelected = selectedConsumptionType == index;
    return GestureDetector(
      onTap: () => setState(() => selectedConsumptionType = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isSelected ? const Color(0xFF007AFF) : const Color(0xFF86868B)),
        ),
      ),
    );
  }

  Widget _buildStatsRow(List<_StatItem> items) {
    return Row(
      children: items.map((item) {
        return Expanded(
          child: Column(
            children: [
              Text(item.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: item.color)),
              const SizedBox(height: 4),
              Text(item.label, style: const TextStyle(fontSize: 12, color: Color(0xFF86868B), fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 2),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLegend(List<CategoryData> categoryData) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      runSpacing: 10,
      children: categoryData.map((data) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: data.color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(data.name, style: const TextStyle(fontSize: 14, color: Color(0xFF1D1D1F))),
          ],
        );
      }).toList(),
    );
  }
}

// --- YENİ YARDIMCI SINIFLAR ---

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF86868B), fontWeight: FontWeight.w500)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1D1D1F))),
        ],
      ),
    );
  }
}

class ConsumptionData {
  final double currentUsage;
  final double previousUsage;
  final double limit;
  final String unit;
  final String type;

  ConsumptionData({
    required this.currentUsage,
    required this.previousUsage,
    required this.limit,
    required this.unit,
    required this.type,
  });

  double get percentage => limit > 0 ? (currentUsage / limit) * 100 : 0;
  double get changePercentage => previousUsage > 0 ? ((currentUsage - previousUsage) / previousUsage) * 100 : 0;
}

class CategoryData {
  final String name;
  final double amount;
  final Color color;

  CategoryData({required this.name, required this.amount, required this.color});
}

class _StatItem {
  final String value;
  final String label;
  final Color color;

  _StatItem({required this.value, required this.label, required this.color});
}
