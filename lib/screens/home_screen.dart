import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

// Gerekli ekranları import ediyoruz.
import 'package:sayacfaturapp/screens/history_screen.dart';
import 'package:sayacfaturapp/screens/reading_detail_screen.dart';
import 'package:sayacfaturapp/screens/charts_screen.dart';
// YENİ: Oluşturduğumuz profil ekranını import ediyoruz.
import 'package:sayacfaturapp/screens/profile_screen.dart';

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
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(_appBarTitles[_tab]),
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              _buildDashboardTab(),
              const HistoryScreen(),
              const ChartsScreen(),
              // GÜNCELLEME: Profil sekmesi artık yer tutucu değil, gerçek ekranı gösteriyor.
              const ProfileScreen(),
            ],
          ),
          bottomNavigationBar: Container(
            height: 65,
            decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1)
                ]),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Ana', isActive: _tab == 0, onTap: () => setState(() => _tab = 0)),
                _NavItem(icon: Icons.history_rounded, label: 'Geçmiş', isActive: _tab == 1, onTap: () => setState(() => _tab = 1)),
                _AddButton(onTap: () { Navigator.pushNamed(context, '/newReading'); }),
                _NavItem(icon: Icons.show_chart_rounded, label: 'Grafik', isActive: _tab == 2, onTap: () => setState(() => _tab = 2)),
                _NavItem(icon: Icons.person_rounded, label: 'Profil', isActive: _tab == 3, onTap: () => setState(() => _tab = 3)),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'chatbot',
            tooltip: 'ChatBot',
            mini: true,
            backgroundColor: Colors.white,
            foregroundColor: Theme.of(context).colorScheme.primary,
            elevation: 3,
            onPressed: () {},
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab() {
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
          return const Center(
            child: Text('Henüz hiç okuma kaydetmediniz.\nEklemek için + butonuna basın.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
          );
        }
        final readings = snapshot.data!.docs.map((doc) => MeterReading.fromSnapshot(doc)).toList();
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _WelcomeChartCard(userName: _currentUser?.displayName, readings: readings),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Son Okumalar', style: Theme.of(context).textTheme.titleLarge),
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

  /// Liste elemanını oluşturan metod
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.15), child: Icon(iconData, color: iconColor)),
        title: Text(
          reading.meterName ?? reading.installationId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          (reading.meterName != null ? '${reading.installationId}\n' : '') +
              '${reading.readingValue} ${reading.unit ?? ''} | ${DateFormat('dd MMM, HH:mm', 'tr_TR').format(reading.readingTime)}',
        ),
        trailing: reading.invoiceAmount != null ? Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(reading.invoiceAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)) : null,
        isThreeLine: reading.meterName != null,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ReadingDetailScreen(reading: reading),
          ));
        },
      ),
    );
  }
}

class _MonthlyTotal {
  final DateTime month;
  final double total;
  _MonthlyTotal(this.month, this.total);
}

class _WelcomeChartCard extends StatelessWidget {
  const _WelcomeChartCard({this.userName, required this.readings});

  final String? userName;
  final List<MeterReading> readings;

  List<_MonthlyTotal> _getMonthlyInvoiceTotals() {
    final Map<String, double> totalsMap = {};
    final Map<String, DateTime> monthDateMap = {};

    for (var reading in readings) {
      if (reading.invoiceAmount != null && reading.invoiceAmount! > 0) {
        final monthKey = DateFormat('yyyy-MM').format(reading.readingTime);
        totalsMap.update(monthKey, (value) => value + reading.invoiceAmount!,
            ifAbsent: () => reading.invoiceAmount!);
        monthDateMap.putIfAbsent(monthKey, () => reading.readingTime);
      }
    }

    final List<_MonthlyTotal> result = totalsMap.entries.map((entry) {
      return _MonthlyTotal(monthDateMap[entry.key]!, entry.value);
    }).toList();

    result.sort((a, b) => b.month.compareTo(a.month));

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final monthlyData =
    _getMonthlyInvoiceTotals().take(6).toList().reversed.toList();

    final spots = <FlSpot>[];
    final monthLabels = <String>[];

    for (int i = 0; i < monthlyData.length; i++) {
      spots.add(FlSpot(i.toDouble(), monthlyData[i].total));
      monthLabels.add(DateFormat('MMM', 'tr_TR').format(monthlyData[i].month));
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hoşgeldin, ${userName ?? 'Kullanıcı'}!',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Aylık Fatura Harcamanız',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            if (spots.isEmpty)
              const Center(
                  heightFactor: 3,
                  child: Text('Grafik için fatura verisi bulunamadı.'))
            else
              AspectRatio(
                aspectRatio: 1.7,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() < monthLabels.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(monthLabels[value.toInt()],
                                    style: const TextStyle(fontSize: 10)),
                              );
                            }
                            return const Text('');
                          },
                          reservedSize: 22,
                        ),
                      ),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: Theme.of(context).primaryColor,
                        barWidth: 4,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color:
                          Theme.of(context).primaryColor.withOpacity(0.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon,
        required this.label,
        required this.isActive,
        required this.onTap});

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
    isActive ? Theme.of(context).colorScheme.primary : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.add_circle, size: 36, color: Colors.blue),
          SizedBox(height: 2),
          Text('Sayaç Ekle',
              style: TextStyle(color: Colors.blue, fontSize: 12)),
        ],
      ),
    );
  }
}
