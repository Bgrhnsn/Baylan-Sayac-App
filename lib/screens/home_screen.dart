import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:sayacfaturapp/screens/charts_screen.dart';
import 'package:sayacfaturapp/screens/history_screen.dart';
import 'package:sayacfaturapp/screens/new_reading_screen.dart';
import 'package:sayacfaturapp/screens/profile_screen.dart';
import 'package:sayacfaturapp/screens/reading_detail_screen.dart';
import 'package:sayacfaturapp/theme/custom_components.dart';

// YENİ: ChartsScreen'den gelen veri modeli
class ChartDataPoint {
  final String label; // Örn: 'Oca', 'Şub'
  final double value;
  final DateTime date;

  ChartDataPoint({required this.label, required this.value, required this.date});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final List<String> _appBarTitles = ['Genel Bakış', 'Geçmiş Kayıtlar', 'Grafikler', 'Profil'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final List<Widget> tabs = [
      _buildDashboardTab(),
      const HistoryScreen(),
      const ChartsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitles[_tab]),
        automaticallyImplyLeading: false,
      ),
      body: IndexedStack(
        index: _tab,
        children: tabs,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'chatbot',
        tooltip: 'ChatBot',
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.primary,
        elevation: 4,
        child: const Icon(Icons.chat_bubble_outline_rounded),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('ChatBot'),
              content: const Text('Bu özellik yakında eklenecektir.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        surfaceTintColor: theme.colorScheme.surface,
        elevation: 8,
        height: 80,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(child: _NavItem(icon: Icons.home_rounded, label: 'Ana Sayfa', isActive: _tab == 0, onTap: () => setState(() => _tab = 0))),
            Expanded(child: _NavItem(icon: Icons.history_rounded, label: 'Geçmiş', isActive: _tab == 1, onTap: () => setState(() => _tab = 1))),
            Expanded(child: _AddButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NewReadingScreen())))),
            Expanded(child: _NavItem(icon: Icons.bar_chart_rounded, label: 'Grafik', isActive: _tab == 2, onTap: () => setState(() => _tab = 2))),
            Expanded(child: _NavItem(icon: Icons.person_rounded, label: 'Profil', isActive: _tab == 3, onTap: () => setState(() => _tab = 3))),
          ],
        ),
      ),
    );
  }

  /// Ana Ekran sekmesini oluşturan ana widget.
  Widget _buildDashboardTab() {
    final theme = Theme.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(_currentUser?.uid).collection('readings').orderBy('readingTime', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'Henüz hiç okuma kaydetmediniz.\nEklemek için + butonuna basın.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
            ),
          );
        }
        final readings = snapshot.data!.docs.map((doc) => MeterReading.fromSnapshot(doc)).toList();

        // YENİ: Grafik için veriyi işle
        final invoiceData = _processInvoiceDataForHome(readings);

        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // YENİ: Eski kart yerine yeni grafik metodu çağrılıyor.
            _buildHomeScreenMonthlyChart(invoiceData),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Son Okumalar', style: theme.textTheme.titleLarge),
                if (readings.length > 3)
                  TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('Tümünü Gör')),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: min(readings.length, 3),
              itemBuilder: (context, index) {
                return _buildReadingListItem(context, readings[index]);
              },
            ),
          ],
        );
      },
    );
  }

  /// Sadece ana ekran grafiği için fatura verilerini işleyen metod.
  List<ChartDataPoint> _processInvoiceDataForHome(List<MeterReading> readings) {
    final Map<String, double> totalsMap = {};
    final Map<String, DateTime> monthDateMap = {};

    // Son 6 ayın verisini almak için bir sınır tarih belirle
    final sixMonthsAgo = DateTime(DateTime.now().year, DateTime.now().month - 5, 1);

    for (var reading in readings) {
      if (reading.invoiceAmount != null && reading.invoiceAmount! > 0 && reading.readingTime.isAfter(sixMonthsAgo)) {
        final monthKey = DateFormat('yyyy-MM').format(reading.readingTime);
        totalsMap.update(monthKey, (value) => value + reading.invoiceAmount!, ifAbsent: () => reading.invoiceAmount!);
        monthDateMap.putIfAbsent(monthKey, () => reading.readingTime);
      }
    }

    final List<ChartDataPoint> result = totalsMap.entries.map((entry) {
      final date = monthDateMap[entry.key]!;
      return ChartDataPoint(
        label: DateFormat('MMM', 'tr_TR').format(date),
        value: entry.value,
        date: date,
      );
    }).toList();

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// YENİ: Ana ekrandaki aylık fatura grafiğini oluşturan metod.
  Widget _buildHomeScreenMonthlyChart(List<ChartDataPoint> data) {
    if (data.length < 2) {
      return _buildChartCard(
          title: 'Aylık Fatura Tutarı',
          period: 'Yeterli Veri Yok',
          child: const SizedBox(height: 200, child: Center(child: Text('Karşılaştırma için en az 2 aylık fatura verisi gerekli.'))));
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

  /// Son okumalar listesindeki her bir öğeyi oluşturan widget.
  Widget _buildReadingListItem(BuildContext context, MeterReading reading) {
    final theme = Theme.of(context);
    final IconData iconData;
    final Color iconColor;
    if (reading.unit == 'kWh') {
      iconData = Icons.electric_bolt;
      iconColor = const Color(0xFFFFC300); // Elektrik için yeni renk
    } else if (reading.unit == 'm³') {
      iconData = Icons.water_drop;
      iconColor = const Color(0xFF007AFF); // Su için mavi tonu
    } else {
      iconData = Icons.help_outline;
      iconColor = Colors.grey;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: AppStyledCard(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.15), child: Icon(iconData, color: iconColor)),
          title: Text(reading.meterName ?? reading.installationId, style: theme.textTheme.titleMedium),
          subtitle: Text('${reading.readingValue} ${reading.unit ?? ''} | ${DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(reading.readingTime)}', style: theme.textTheme.bodyMedium),
          trailing: reading.invoiceAmount != null ? Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(reading.invoiceAmount), style: theme.textTheme.titleMedium) : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => ReadingDetailScreen(reading: reading))),
        ),
      ),
    );
  }
}

// =======================================================================
// YARDIMCI WIDGET'LAR VE SINIFLAR
// =======================================================================

/// YENİ: Grafik kartları için genel çerçeve widget'ı.
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

/// YENİ: Grafik altındaki istatistik satırını oluşturan widget.
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

/// YENİ: İstatistik öğesi için veri sınıfı.
class _StatItem {
  final String value;
  final String label;
  final Color color;

  _StatItem({required this.value, required this.label, required this.color});
}

/// Navigasyon barındaki her bir öğe için widget.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.isActive, required this.onTap});

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive ? theme.colorScheme.primary : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 1),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}

/// Navigasyon barındaki "Ekle" butonu.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_circle, size: 32, color: theme.colorScheme.primary),
          const SizedBox(height: 2),
          Text('Ekle', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
