import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';

/// Kullanıcı profili, istatistikler ve hesap yönetimi ekranı.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Çıkış yapma fonksiyonu
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      // Tüm geçmişi temizleyerek login ekranına yönlendir
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  // Şifre sıfırlama e-postası gönderme fonksiyonu
  Future<void> _resetPassword() async {
    if (_currentUser?.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre sıfırlama linki göndermek için e-posta adresi bulunamadı.')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _currentUser!.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_currentUser!.email} adresine şifre sıfırlama linki gönderildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bir hata oluştu: $e')),
        );
      }
    }
  }

  // Hesap silme işlemi için onay dialogu
  Future<void> _showDeleteConfirmation() async {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Hesabı Sil'),
          content: const Text('Bu işlem tüm verilerinizi kalıcı olarak silecektir ve geri alınamaz. Devam etmek istediğinizden emin misiniz?'),
          actions: [
            TextButton(
              child: const Text('İptal'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Hesabımı Sil'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _deleteAccount();
              },
            ),
          ],
        );
      },
    );
  }

  // Hesabı ve ilgili verileri silen fonksiyon
  Future<void> _deleteAccount() async {
    try {
      if (_currentUser == null) return;

      // Firestore'daki tüm okuma verilerini sil
      final readingsQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('readings')
          .get();
      for (var doc in readingsQuery.docs) {
        await doc.reference.delete();
      }

      // Kullanıcının ana dokümanını sil (varsa)
      await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).delete();

      // Firebase Auth'dan kullanıcıyı sil
      await _currentUser!.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hesabınız başarıyla silindi.')),
        );
        // Login ekranına yönlendir
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = 'Hesap silinirken bir hata oluştu: ${e.message}';
        // Yeniden kimlik doğrulama gerektiren hata için kullanıcıyı bilgilendir
        if (e.code == 'requires-recent-login') {
          message = 'Bu hassas bir işlemdir. Lütfen çıkış yapıp tekrar giriş yaptıktan sonra deneyin.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Beklenmedik bir hata oluştu: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        // Kullanıcının istatistiklerini almak için verileri dinle
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser?.uid)
            .collection('readings')
            .snapshots(),
        builder: (context, snapshot) {
          int totalReadings = 0;
          int uniqueMeters = 0;

          if (snapshot.hasData) {
            final readings = snapshot.data!.docs.map((doc) => MeterReading.fromSnapshot(doc)).toList();
            totalReadings = readings.length;
            uniqueMeters = readings.map((r) => r.installationId).toSet().length;
          }

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // 1. Kullanıcı Bilgi Kartı
              _buildUserInfoCard(),
              const SizedBox(height: 24),

              // 2. İstatistik Kartları
              Row(
                children: [
                  Expanded(child: _StatCard(count: totalReadings.toString(), label: 'Toplam Kayıt', icon: Icons.receipt_long, color: Colors.blue)),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(count: uniqueMeters.toString(), label: 'Kayıtlı Sayaç', icon: Icons.electrical_services, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 24),

              // 3. Hesap Yönetimi
              _buildSectionTitle('Hesap Yönetimi'),
              _ActionTile(title: 'Şifremi Değiştir', icon: Icons.lock_outline, onTap: _resetPassword),
              _ActionTile(title: 'Çıkış Yap', icon: Icons.logout, onTap: _signOut),
              const SizedBox(height: 16),

              // 4. Tehlikeli Alan
              _buildSectionTitle('Tehlikeli Alan'),
              _ActionTile(
                title: 'Hesabımı Sil',
                icon: Icons.delete_forever_outlined,
                color: Colors.red,
                onTap: _showDeleteConfirmation,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUserInfoCard() {
    String initials = _currentUser?.displayName?.isNotEmpty == true
        ? _currentUser!.displayName!.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : (_currentUser?.email?[0] ?? '?').toUpperCase();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(initials, style: const TextStyle(fontSize: 24, color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentUser?.displayName ?? 'Kullanıcı Adı',
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentUser?.email ?? 'E-posta adresi bulunamadı.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 16.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

/// İstatistikleri gösteren küçük kart widget'ı.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.count, required this.label, required this.icon, required this.color});
  final String count;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(count, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Eylem listesi elemanı widget'ı.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.title, required this.icon, this.color, required this.onTap});
  final String title;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: color ?? Theme.of(context).iconTheme.color),
        title: Text(title, style: TextStyle(color: color)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
