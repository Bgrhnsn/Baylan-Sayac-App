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
  ChartDataPoint(this.label, this.value);
}

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Filtreleme ve arayüz state'leri
  int _selectedChartType = 0; // 0: Tutar, 1: Tüketim, 2: Dağılım
  String? _selectedMeterId;
  DateTimeRange? _selectedDateRange;
  int _touchedIndex = -1;
  // GÜNCELLEME: Hızlı tarih filtreleri için state
  int _selectedQuickFilter = 1; // 0: Son 3 Ay, 1: Son 6 Ay, 2: Bu Yıl

  @override
  void initState() {
    super.initState();
    // Başlangıçta "Son 6 Ay" filtresini uygula
    _applyQuickFilter(1);
  }

  /// Verileri işleyip grafikler için hazır hale getiren metod.
  Map<String, dynamic> _processReadings(List<MeterReading> readings) {
    final Map<String, double> monthlyInvoiceTotals = {};
    final Map<String, double> monthlyConsumptionTotals = {};
    final Map<String, double> distributionTotals = {'kWh': 0.0, 'm³': 0.0};

    for (var reading in readings) {
      final monthKey = DateFormat('yyyy-MM').format(reading.readingTime);
      if (reading.invoiceAmount != null && reading.invoiceAmount! > 0) {
        monthlyInvoiceTotals.update(monthKey, (value) => value + reading.invoiceAmount!, ifAbsent: () => reading.invoiceAmount!);
        if (reading.unit != null) {
          distributionTotals.update(reading.unit!, (value) => value + reading.invoiceAmount!, ifAbsent: () => reading.invoiceAmount!);
        }
      }
      if (reading.readingValue > 0) {
        monthlyConsumptionTotals.update(monthKey, (value) => value + reading.readingValue, ifAbsent: () => reading.readingValue);
      }
    }

    final invoiceData = monthlyInvoiceTotals.entries
        .map((e) => ChartDataPoint(DateFormat('MMM', 'tr_TR').format(DateFormat('yyyy-MM').parse(e.key)), e.value))
        .toList();

    final consumptionData = monthlyConsumptionTotals.entries
        .map((e) => ChartDataPoint(DateFormat('MMM', 'tr_TR').format(DateFormat('yyyy-MM').parse(e.key)), e.value))
        .toList();

    return {
      'invoice': invoiceData,
      'consumption': consumptionData,
      'distribution': distributionTotals,
    };
  }

  /// GÜNCELLEME: Hızlı tarih filtresi seçildiğinde tarih aralığını ayarlayan metod.
  void _applyQuickFilter(int index) {
    setState(() {
      _selectedQuickFilter = index;
      final now = DateTime.now();
      switch (index) {
        case 0: // Son 3 Ay
          _selectedDateRange = DateTimeRange(start: DateTime(now.year, now.month - 2, 1), end: now);
          break;
        case 1: // Son 6 Ay
          _selectedDateRange = DateTimeRange(start: DateTime(now.year, now.month - 5, 1), end: now);
          break;
        case 2: // Bu Yıl
          _selectedDateRange = DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser?.uid)
          .collection('readings')
          .orderBy('readingTime')
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
            child: Text('Grafik oluşturmak için henüz hiç veri eklemediniz.', style: TextStyle(fontSize: 16, color: Colors.grey)),
          );
        }

        final allReadings = snapshot.data!.docs.map((doc) => MeterReading.fromSnapshot(doc)).toList();

        final uniqueMeters = <String, String>{};
        for (var reading in allReadings) {
          uniqueMeters[reading.installationId] = reading.meterName ?? reading.installationId;
        }

        final filteredReadings = allReadings.where((reading) {
          final meterMatch = _selectedMeterId == null || reading.installationId == _selectedMeterId;
          final dateMatch = _selectedDateRange == null ||
              (reading.readingTime.isAfter(_selectedDateRange!.start) &&
                  reading.readingTime.isBefore(_selectedDateRange!.end.add(const Duration(days: 1))));
          return meterMatch && dateMatch;
        }).toList();

        final processedData = _processReadings(filteredReadings);
        final invoiceData = processedData['invoice'] as List<ChartDataPoint>;
        final consumptionData = processedData['consumption'] as List<ChartDataPoint>;
        final distributionData = processedData['distribution'] as Map<String, double>;

        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildFilterBar(context, uniqueMeters),
            const SizedBox(height: 16),
            // GÜNCELLEME: Akıllı özet kartları eklendi.
            _buildSummaryCards(filteredReadings, invoiceData, consumptionData),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Tutar'), icon: Icon(Icons.show_chart)),
                ButtonSegment(value: 1, label: Text('Tüketim'), icon: Icon(Icons.bar_chart)),
                ButtonSegment(value: 2, label: Text('Dağılım'), icon: Icon(Icons.pie_chart)),
              ],
              selected: {_selectedChartType},
              onSelectionChanged: (newSelection) {
                setState(() => _selectedChartType = newSelection.first);
              },
            ),
            const SizedBox(height: 24),

            if (_selectedChartType == 0)
              _buildChartCard(context, title: 'Aylık Fatura Tutarı (₺)', dataPoints: invoiceData, chart: _buildLineChart(context, invoiceData))
            else if (_selectedChartType == 1)
              _buildChartCard(context, title: 'Aylık Tüketim Miktarı', dataPoints: consumptionData, chart: _buildBarChart(context, consumptionData))
            else
              _buildPieChartCard(context, title: 'Fatura Dağılımı', distributionData: distributionData)
          ],
        );
      },
    );
  }

  /// Filtreleme barını oluşturan widget.
  Widget _buildFilterBar(BuildContext context, Map<String, String> uniqueMeters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Filtreler', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedMeterId,
          hint: const Text('Tüm Sayaçlar'),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.electrical_services),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Tüm Sayaçlar')),
            ...uniqueMeters.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(entry.value))),
          ],
          onChanged: (value) => setState(() => _selectedMeterId = value),
        ),
        const SizedBox(height: 12),
        // GÜNCELLEME: Hızlı tarih filtreleri
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: ChoiceChip(label: const Text('Son 3 Ay'), selected: _selectedQuickFilter == 0, onSelected: (val) => _applyQuickFilter(0))),
            const SizedBox(width: 8),
            Expanded(child: ChoiceChip(label: const Text('Son 6 Ay'), selected: _selectedQuickFilter == 1, onSelected: (val) => _applyQuickFilter(1))),
            const SizedBox(width: 8),
            Expanded(child: ChoiceChip(label: const Text('Bu Yıl'), selected: _selectedQuickFilter == 2, onSelected: (val) => _applyQuickFilter(2))),
          ],
        ),
        if (_selectedMeterId != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() { _selectedMeterId = null; }),
              child: const Text('Sayaç Filtresini Temizle'),
            ),
          ),
      ],
    );
  }

  /// GÜNCELLEME: Akıllı özet kartlarını oluşturan widget.
  Widget _buildSummaryCards(List<MeterReading> readings, List<ChartDataPoint> invoiceData, List<ChartDataPoint> consumptionData) {
    if (readings.isEmpty) return const SizedBox.shrink();

    // Hesaplamalar
    final totalInvoice = readings.fold(0.0, (sum, item) => sum + (item.invoiceAmount ?? 0));
    final averageInvoice = invoiceData.isNotEmpty ? invoiceData.map((e) => e.value).reduce((a, b) => a + b) / invoiceData.length : 0.0;

    ChartDataPoint? maxConsumption;
    if (consumptionData.isNotEmpty) {
      maxConsumption = consumptionData.reduce((curr, next) => curr.value > next.value ? curr : next);
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(title: 'Dönem Toplamı', value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(totalInvoice), icon: Icons.functions, color: Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Aylık Ortalama', value: NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(averageInvoice), icon: Icons.show_chart, color: Colors.blue)),
          ],
        ),
        if (maxConsumption != null) ...[
          const SizedBox(height: 12),
          _SummaryCard(title: 'Rekor Tüketim', value: '${maxConsumption.value.toStringAsFixed(1)} kWh/m³ (${maxConsumption.label})', icon: Icons.trending_up, color: Colors.red),
        ]
      ],
    );
  }

  Widget _buildChartCard(BuildContext context, {required String title, required List<ChartDataPoint> dataPoints, required Widget chart}) {
    if (dataPoints.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(height: 250, child: Center(child: Text('Bu filtreler için veri bulunamadı.'))),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(height: 250, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChartCard(BuildContext context, {required String title, required Map<String, double> distributionData}) {
    final total = distributionData.values.fold(0.0, (sum, item) => sum + item);
    if (total == 0) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(height: 300, child: Center(child: Text('Dağılım grafiği için fatura verisi bulunamadı.'))),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: InteractivePieChart(data: distributionData),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if(distributionData['kWh']! > 0) _Indicator(color: Colors.orangeAccent, text: 'Elektrik', isSquare: false),
                if(distributionData['kWh']! > 0 && distributionData['m³']! > 0) const SizedBox(width: 16),
                if(distributionData['m³']! > 0) _Indicator(color: Colors.blueAccent, text: 'Su', isSquare: false),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(BuildContext context, List<ChartDataPoint> dataPoints) {
    final spots = <FlSpot>[];
    for (int i = 0; i < dataPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), dataPoints[i].value));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
            if (value.toInt() < dataPoints.length) {
              return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(dataPoints[value.toInt()].label, style: const TextStyle(fontSize: 10)));
            }
            return const Text('');
          })),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(spot.y)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: [TextSpan(text: dataPoints[spot.spotIndex].label, style: const TextStyle(fontWeight: FontWeight.normal))],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).primaryColor,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Theme.of(context).primaryColor.withOpacity(0.2)),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(BuildContext context, List<ChartDataPoint> dataPoints) {
    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < dataPoints.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: dataPoints[i].value,
              color: dataPoints[i].value > 100 ? Colors.orangeAccent : Colors.blueAccent,
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: barGroups,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
            if (value.toInt() < dataPoints.length) {
              return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(dataPoints[value.toInt()].label, style: const TextStyle(fontSize: 10)));
            }
            return const Text('');
          })),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toStringAsFixed(1)}\n',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                children: [TextSpan(text: dataPoints[group.x].label, style: const TextStyle(fontWeight: FontWeight.normal))],
              );
            },
          ),
        ),
      ),
    );
  }
}

class InteractivePieChart extends StatefulWidget {
  final Map<String, double> data;
  const InteractivePieChart({required this.data, super.key});

  @override
  State<InteractivePieChart> createState() => _InteractivePieChartState();
}

class _InteractivePieChartState extends State<InteractivePieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final totalValue = widget.data.values.fold(0.0, (sum, item) => sum + item);
    final activeSections = widget.data.entries.where((e) => e.value > 0).toList();

    return PieChart(
      PieChartData(
        pieTouchData: PieTouchData(
          touchCallback: (event, pieTouchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  pieTouchResponse == null ||
                  pieTouchResponse.touchedSection == null) {
                _touchedIndex = -1;
              } else {
                _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
              }
            });
          },
        ),
        borderData: FlBorderData(show: false),
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: List.generate(activeSections.length, (i) {
          final isTouched = i == _touchedIndex;
          final entry = activeSections[i];
          final percentage = (entry.value / totalValue * 100);

          return PieChartSectionData(
            color: entry.key == 'kWh' ? Colors.orangeAccent : Colors.blueAccent,
            value: entry.value,
            title: '${percentage.toStringAsFixed(0)}%',
            radius: isTouched ? 60.0 : 50.0,
            titleStyle: TextStyle(
              fontSize: isTouched ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.color,
    required this.text,
    required this.isSquare,
    this.size = 16,
    this.textColor,
  });
  final Color color;
  final String text;
  final bool isSquare;
  final double size;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        )
      ],
    );
  }
}

/// GÜNCELLEME: Özet kartları için yeni bir widget.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
