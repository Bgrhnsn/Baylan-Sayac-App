import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sayacfaturapp/models/meter_reading.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Kullanıcı profili, istatistikler ve hesap yönetimi ekranı.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {//profil sayfası mantığını ve durumunu yönetir
  final User? _currentUser = FirebaseAuth.instance.currentUser;//mevcut kullanıcıyı alır

  // Çıkış yapma fonksiyonu
  Future<void> _signOut() async {
    await GoogleSignIn().signOut();//google ile giriş yaptan çık
    await FirebaseAuth.instance.signOut();//firebase authtan çık
    if (mounted) {
      // Tüm geçmişi temizleyerek login ekranına yönlendir
      Navigator.of(context).pushNamedAndRemoveUntil('/LoginScreen', (route) => false);
    }
  }

  // Şifre sıfırlama e-postası gönderme fonksiyonu
  Future<void> _resetPassword() async {
    // 1. Mevcut kullanıcının e-posta adresi var mı diye kontrol et.
    if (_currentUser?.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre sıfırlama linki göndermek için e-posta adresi bulunamadı.')),
      );
      return;
    }
    try {
      // 2. Firebase'e e-posta gönderme komutunu ver.
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _currentUser!.email!);

      // 3. İşlem başarılıysa kullanıcıyı bilgilendir.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_currentUser!.email} adresine şifre sıfırlama linki gönderildi.')),
        );
      }
    } catch (e) {
      // 4. Bir hata olursa kullanıcıyı bilgilendir.
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

  // kullanıcı onayından sonra çalışır ve Hesabı ve ilgili verileri silen fonksiyon
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
  Widget build(BuildContext context) {//ekran arayüz
    return Scaffold(
      // YENİ: Arka plan rengi diğer ekranlarla uyumlu hale getirildi.
      backgroundColor: const Color(0xFFF5F5F7),
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
                  Expanded(child: _StatCard(count: totalReadings.toString(), label: 'Toplam Kayıt', icon: Icons.receipt_long, color: const Color(0xFF007AFF))),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(count: uniqueMeters.toString(), label: 'Kayıtlı Sayaç', icon: Icons.electrical_services, color: const Color(0xFF30D158))),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Hesap Yönetimi
              _buildSectionTitle('Hesap Yönetimi'),
              _ActionTile(title: 'Şifremi Değiştir', icon: Icons.lock_outline, onTap: _resetPassword),
              _ActionTile(title: 'Çıkış Yap', icon: Icons.logout, onTap: _signOut),

              // 4. Tehlikeli Alan
              _buildSectionTitle('Tehlikeli Alan'),
              _ActionTile(
                title: 'Hesabımı Sil',
                icon: Icons.delete_forever_outlined,
                color: const Color(0xFFFF3B30),
                onTap: _showDeleteConfirmation,
              ),
            ],
          );
        },
      ),
    );
  }

  // kullanıcı adını e postasının baş harflerinden ibr avatar kartı
  Widget _buildUserInfoCard() {
    String initials = _currentUser?.displayName?.isNotEmpty == true
        ? _currentUser!.displayName!.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : (_currentUser?.email?[0] ?? '?').toUpperCase();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFE5E5EA).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF007AFF),
            child: Text(initials, style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUser?.displayName ?? 'Kullanıcı Adı',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1D1D1F)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _currentUser?.email ?? 'E-posta adresi bulunamadı.',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF86868B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// YENİ: Modern arayüze uygun bölüm başlığı.
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF86868B),
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// toplam kayıt ve kayıtlı sayaç kartı
class _StatCard extends StatelessWidget {
  const _StatCard({required this.count, required this.label, required this.icon, required this.color});
  final String count;
  final String label;
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
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(count, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1D1D1F))),
          Text(label, style: const TextStyle(color: Color(0xFF86868B), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// şifre değiştirme , çıkış yapma hesap silme butonları
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.title, required this.icon, this.color, required this.onTap});
  final String title;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = color ?? const Color(0xFF1D1D1F);
    final iconColor = color ?? const Color(0xFF86868B);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.w500, fontSize: 16))),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
