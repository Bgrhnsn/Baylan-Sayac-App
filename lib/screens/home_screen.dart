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
            Expanded(
              child: _NavItem(icon: Icons.home_rounded, label: 'Ana Sayfa', isActive: _tab == 0, onTap: () => setState(() => _tab = 0)),
            ),
            Expanded(
              child: _NavItem(icon: Icons.history_rounded, label: 'Geçmiş', isActive: _tab == 1, onTap: () => setState(() => _tab = 1)),
            ),
            Expanded(
              child: _AddButton(onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NewReadingScreen()),
                );
              }),
            ),
            Expanded(
              child: _NavItem(icon: Icons.bar_chart_rounded, label: 'Grafik', isActive: _tab == 2, onTap: () => setState(() => _tab = 2)),
            ),
            Expanded(
              child: _NavItem(icon: Icons.person_rounded, label: 'Profil', isActive: _tab == 3, onTap: () => setState(() => _tab = 3)),
            ),
          ],
        ),
      ),
    );
  }

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
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _WelcomeChartCard(userName: _currentUser?.displayName ?? _currentUser?.email, readings: readings),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: AppStyledCard(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.15), child: Icon(iconData, color: iconColor)),
          title: Text(
            reading.meterName ?? reading.installationId,
            style: theme.textTheme.titleMedium,
          ),
          subtitle: Text(
            '${reading.readingValue} ${reading.unit ?? ''} | ${DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(reading.readingTime)}',
            style: theme.textTheme.bodyMedium,
          ),
          trailing: reading.invoiceAmount != null ? Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(reading.invoiceAmount), style: theme.textTheme.titleMedium) : null,
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

// =======================================================================
// YARDIMCI WIDGET'LAR
// Okunabilirliği artırmak için dosyanın en altına taşındı.
// =======================================================================

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
        totalsMap.update(monthKey, (value) => value + reading.invoiceAmount!, ifAbsent: () => reading.invoiceAmount!);
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
    final theme = Theme.of(context);
    final monthlyData = _getMonthlyInvoiceTotals().take(6).toList().reversed.toList();

    final spots = <FlSpot>[];
    final monthLabels = <String>[];

    for (int i = 0; i < monthlyData.length; i++) {
      spots.add(FlSpot(i.toDouble(), monthlyData[i].total));
      monthLabels.add(DateFormat('MMM', 'tr_TR').format(monthlyData[i].month));
    }

    return AppStyledCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hoş geldin, ${userName ?? 'Kullanıcı'}!', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Aylık Fatura Harcamanız', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            if (spots.isEmpty)
              SizedBox(
                  height: 150,
                  child: Center(child: Text('Grafik için fatura verisi bulunamadı.', style: theme.textTheme.bodyMedium)))
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
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(monthLabels[value.toInt()], style: theme.textTheme.bodySmall),
                              );
                            }
                            return const Text('');
                          },
                          reservedSize: 30,
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: theme.colorScheme.primary,
                        barWidth: 4,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: theme.colorScheme.primary.withOpacity(0.2),
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
        // HATA DÜZELTMESİ: Column'un dikeyde taşmasını engeller.
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
        // HATA DÜZELTMESİ: Column'un dikeyde taşmasını engeller.
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