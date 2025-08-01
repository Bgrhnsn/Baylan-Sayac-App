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
      // _processReadings metodunda bu bölümü güncelleyin
      if (reading.readingValue != null && reading.readingValue! > 0 && reading.unit != null) {
        final key = '$monthKey-${reading.unit!}';
        monthlyConsumptionTotalsByUnit.update(key, (value) => value + reading.readingValue!, ifAbsent: () => reading.readingValue!);
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
                              _buildConsumptionComparisonChart(consumptionData)
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

  /// YENİ: Grafik eksenleri için "güzel" aralıklar ve maksimum değer hesaplayan yardımcı metot.
  Map<String, double> _calculateNiceAxisValues(double maxValue) {
    // Eğer hiç veri yoksa veya maksimum değer 0 ise, varsayılan bir aralık döndür.
    if (maxValue <= 0) {
      return {'maxY': 100.0, 'interval': 25.0};
    }

    // Ekranda yaklaşık olarak kaç adet çizgi/etiket görmek istediğimizi belirtiyoruz.
    const int numberOfTicks = 4;
    final double rawInterval = maxValue / numberOfTicks;

    // Aralığın büyüklüğünü (10'un kuvveti olarak) buluyoruz.
    final double magnitude = pow(10, (log(rawInterval) / log(10)).floor()).toDouble();
    final double residual = rawInterval / magnitude;

    // Bu büyüklüğe en uygun "güzel" çarpanı (1, 2, veya 5) seçiyoruz.
    double niceMultiplier;
    if (residual > 5) {
      niceMultiplier = 10;
    } else if (residual > 2) {
      niceMultiplier = 5;
    } else if (residual > 1) {
      niceMultiplier = 2;
    } else {
      niceMultiplier = 1;
    }

    final double niceInterval = niceMultiplier * magnitude;

    // Yeni "güzel" aralığımıza göre eksenin yeni maksimum değerini hesaplıyoruz.
    final double niceMaxValue = (maxValue / niceInterval).ceil() * niceInterval;

    return {'maxY': niceMaxValue, 'interval': niceInterval};
  }


  /// GÜNCELLEME: Aylık fatura grafiği artık "güzel" eksen değerleri kullanıyor.
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

    // Y eksenindeki maksimum değeri bul
    final dataMaxY = data.isEmpty ? 0.0 : data.map((d) => d.value).reduce(max);

    // YENİ: Akıllı eksen değerlerini hesapla
    final axisValues = _calculateNiceAxisValues(dataMaxY);
    final niceMaxY = axisValues['maxY']!;
    final niceInterval = axisValues['interval']!;

    return _buildChartCard(
      title: 'Aylık Fatura Tutarı',
      period: DateFormat('yyyy').format(data.last.date),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: niceInterval, getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFF2F2F7), strokeWidth: 1, dashArray: [5, 5])),
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
                      interval: niceInterval, // GÜNCELLEME
                      getTitlesWidget: (double value, TitleMeta meta) => Text('₺${(value / 1000).toStringAsFixed(1)}k', style: const TextStyle(color: Color(0xFF86868B), fontWeight: FontWeight.w500, fontSize: 12)),
                      reservedSize: 42,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: data.length - 1.toDouble(),
                minY: 0, // GÜNCELLEME: Eksen her zaman 0'dan başlasın
                maxY: niceMaxY, // GÜNCELLEME
                lineBarsData: [
                  LineChartBarData(
                    spots: data.asMap().entries.map((entry) => FlSpot(entry.key.toDouble(), entry.value.value)).toList(),
                    isCurved: true,
                    gradient: const LinearGradient(colors: [Color(0xFF007AFF), Color(0xFF007AFF)]),
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

  Widget _buildConsumptionComparisonChart(Map<String, double> consumptionData) {
    if (consumptionData.length < 2) {
      return _buildChartCard(
          title: 'Aylık Fatura Tutarı',
          period: 'Yeterli Veri Yok',
          child: const SizedBox(height: 200, child: Center(child: Text('Karşılaştırma için en az 2 aylık veri gerekli.'))));
    }
    try {
      // 1) Veri hazırlığı (değişmedi)
      final safeConsumptionData = consumptionData;
      final Set<String> availableMonths = {};
      safeConsumptionData.keys.forEach((key) {
        final parts = key.split('-');
        if (parts.length >= 2) availableMonths.add('${parts[0]}-${parts[1]}');
      });
      final sortedMonths = availableMonths.toList()..sort();
      final last6Months = sortedMonths.length > 6
          ? sortedMonths.sublist(sortedMonths.length - 6)
          : sortedMonths;

      final monthlyData = <Map<String, dynamic>>[];
      for (final monthKey in last6Months) {
        try {
          final monthDate = DateFormat('yyyy-MM').parse(monthKey);
          monthlyData.add({
            'month': DateFormat('MMM', 'tr_TR').format(monthDate),
            'date': monthDate,
            'kWh': safeConsumptionData['$monthKey-kWh'] ?? 0,
            'm3': safeConsumptionData['$monthKey-m³'] ?? 0,
          });
        } catch (_) {
          debugPrint('Hatalı ay formatı atlanıyor: $monthKey');
        }
      }

      if (monthlyData.isEmpty ||
          !monthlyData.any((m) => m['kWh'] > 0 || m['m3'] > 0)) {
        return _buildChartCard(
          title: 'Tüketim Karşılaştırması',
          period: '',
          child: const SizedBox(
              height: 200,
              child: Center(child: Text('Bu dönem için tüketim verisi bulunamadı.'))),
        );
      }

      // 2) Eksen değerleri
      double maxKwh = 0, maxM3 = 0;
      for (final m in monthlyData) {
        maxKwh = max(maxKwh, m['kWh'] as double);
        maxM3 = max(maxM3, m['m3'] as double);
      }
      final axis = _calculateNiceAxisValues(max(maxKwh, maxM3));
      final niceMaxValue = axis['maxY']!;
      final niceInterval = axis['interval']!;

      // 3) Kart
      return _buildChartCard(
        title: 'Tüketim Karşılaştırması',
        period: '', // gri etiket yok
        child: Column(
          children: [
            // Sekmeler
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildTab('Elektrik', 0)),
                  Expanded(child: _buildTab('Su', 1)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4) GRAFİK – kaydırma yok
            LayoutBuilder(
              builder: (context, constraints) {
                // Ekran genişliğine göre çubuk genişliği ayarla
                final barWidth = (constraints.maxWidth /
                    (monthlyData.length * 2)) // her grup + boşluk
                    .clamp(8.0, 22.0);

                return SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      maxY: niceMaxValue,
                      alignment: BarChartAlignment.spaceAround,
                      titlesData: FlTitlesData(
                        rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              return i >= 0 && i < monthlyData.length
                                  ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(monthlyData[i]['month'],
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF86868B))),
                              )
                                  : const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            interval: niceInterval,
                            reservedSize: 42,
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value % niceInterval != 0 && value != 0) {
                                return const SizedBox.shrink();
                              }
                              return Text(value.toInt().toString(),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF86868B)));
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: monthlyData.asMap().entries.map((e) {
                        final i = e.key;
                        final data = e.value;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: selectedConsumptionType == 0
                                  ? data['kWh']
                                  : data['m3'],
                              color: selectedConsumptionType == 0
                                  ? const Color(0xFFFFC300)
                                  : const Color(0xFF007AFF),
                              width: barWidth,
                              borderRadius: BorderRadius.circular(6),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: niceMaxValue,
                                color: const Color(0xFFE5E5EA),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),
            _buildConsumptionInsights(monthlyData),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Tüketim grafiği oluşturulurken hata: $e');
      return _buildChartCard(
        title: 'Tüketim Karşılaştırması',
        period: 'Hata',
        child: const SizedBox(
            height: 200,
            child: Center(child: Text('Grafik yüklenirken bir hata oluştu.'))),
      );
    }
  }


  // --- YARDIMCI WIDGET'LAR ---
  Widget _buildConsumptionInsights(List<Map<String, dynamic>> monthlyData) {
    // Listeyi güvenli bir şekilde kontrol et
    if (monthlyData == null || monthlyData.isEmpty || monthlyData.length < 2) {
      return const SizedBox.shrink();
    }

    try {
      final currentMonth = monthlyData.last;
      final previousMonth = monthlyData[monthlyData.length - 2];

      // Null değerleri güvenli bir şekilde ele al
      final currentUsage = selectedConsumptionType == 0
          ? (currentMonth['kWh'] as double? ?? 0.0)
          : (currentMonth['m3'] as double? ?? 0.0);

      final previousUsage = selectedConsumptionType == 0
          ? (previousMonth['kWh'] as double? ?? 0.0)
          : (previousMonth['m3'] as double? ?? 0.0);

      // Anlamlı veri yoksa gösterme
      if (currentUsage == 0 && previousUsage == 0) {
        return const SizedBox.shrink();
      }

      final change = currentUsage - previousUsage;
      final changePercentage = previousUsage > 0 ? (change / previousUsage) * 100 : 0;

      final unit = selectedConsumptionType == 0 ? 'kWh' : 'm³';
      final type = selectedConsumptionType == 0 ? 'Elektrik' : 'Su';

      Color changeColor = change > 0 ? const Color(0xFFFF3B30) : const Color(0xFF30D158);
      String changeText = change > 0 ? 'artış' : 'azalış';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: change > 0
                ? const Color(0xFFFFF0F0)
                : const Color(0xFFF0FFF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: changeColor.withOpacity(0.3))
        ),
        child: Row(
          children: [
            Icon(
              change > 0 ? Icons.trending_up : Icons.trending_down,
              color: changeColor,
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    '$type tüketiminiz bir önceki fatura dönemine göre ${changePercentage.abs().toStringAsFixed(1)}% $changeText. '
                        '(Bu dönem: ${currentUsage.toStringAsFixed(0)} $unit, Önceki dönem: ${previousUsage.toStringAsFixed(0)} $unit)',
                    style: TextStyle(color: change > 0 ? const Color(0xFF8B0000) : const Color(0xFF006400))
                )
            ),
          ],
        ),
      );
    } catch (e) {
      // Hata durumunda boş widget döndür
      debugPrint('Consumption insights error: $e');
      return const SizedBox.shrink();
    }
  }


  Widget _buildChartCard({
    required String title,
    required String period,        // boş ("") geçilebilir
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFE5E5EA).withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                // 👇 YALNIZCA period doluysa göster
                if (period.trim().isNotEmpty)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      period,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF86868B),
                      ),
                    ),
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
