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
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  // GÜNCELLEME: Şifre değiştirme dialogunu açan fonksiyon
  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Dialog dışına tıklayınca kapanmasını engelle
      builder: (context) {
        // Dialogun kendi state'ini yönetmesi için ayrı bir widget kullanıyoruz.
        return const _ChangePasswordDialog();
      },
    );
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

      final readingsQuery = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).collection('readings').get();
      for (var doc in readingsQuery.docs) {
        await doc.reference.delete();
      }
      await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).delete();
      await _currentUser!.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hesabınız başarıyla silindi.')));
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = 'Hesap silinirken bir hata oluştu: ${e.message}';
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
        stream: FirebaseFirestore.instance.collection('users').doc(_currentUser?.uid).collection('readings').snapshots(),
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
              _buildUserInfoCard(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _StatCard(count: totalReadings.toString(), label: 'Toplam Kayıt', icon: Icons.receipt_long, color: Colors.blue)),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(count: uniqueMeters.toString(), label: 'Kayıtlı Sayaç', icon: Icons.electrical_services, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Hesap Yönetimi'),
              // GÜNCELLEME: onTap artık yeni dialog fonksiyonunu çağırıyor.
              _ActionTile(title: 'Şifremi Değiştir', icon: Icons.lock_outline, onTap: _showChangePasswordDialog),
              _ActionTile(title: 'Çıkış Yap', icon: Icons.logout, onTap: _signOut),
              const SizedBox(height: 16),
              _buildSectionTitle('Tehlikeli Alan'),
              _ActionTile(title: 'Hesabımı Sil', icon: Icons.delete_forever_outlined, color: Colors.red, onTap: _showDeleteConfirmation),
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

/// YENİ: Şifre değiştirme dialogunu ve state'ini yöneten widget.
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSaving = false;
  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı bulunamadı.'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isSaving = false);
      return;
    }

    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: _currentPasswordController.text,
    );

    try {
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_newPasswordController.text);

      if (mounted) {
        Navigator.of(context).pop(); // Dialogu kapat
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifreniz başarıyla güncellendi.'), backgroundColor: Colors.green),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = 'Bir hata oluştu.';
        if (e.code == 'wrong-password') {
          errorMessage = 'Mevcut şifreniz yanlış.';
        } else if (e.code == 'weak-password') {
          errorMessage = 'Yeni şifre çok zayıf. En az 6 karakter olmalı.';
        } else {
          errorMessage = 'Bir hata oluştu: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Şifreyi Değiştir'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentPasswordController,
                obscureText: !_currentPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Mevcut Şifre',
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: IconButton(
                    icon: Icon(_currentPasswordVisible ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _currentPasswordVisible = !_currentPasswordVisible),
                  ),
                ),
                validator: (value) => value!.isEmpty ? 'Lütfen mevcut şifrenizi girin.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPasswordController,
                obscureText: !_newPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Yeni Şifre',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_newPasswordVisible ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _newPasswordVisible = !_newPasswordVisible),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Lütfen yeni bir şifre girin.';
                  if (value.length < 6) return 'Şifre en az 6 karakter olmalıdır.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: !_newPasswordVisible, // Yeni şifre ile aynı görünürlükte olmalı
                decoration: const InputDecoration(
                  labelText: 'Yeni Şifreyi Onayla',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) {
                  if (value != _newPasswordController.text) return 'Şifreler eşleşmiyor.';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _updatePassword,
          child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Güncelle'),
        ),
      ],
    );
  }
}
