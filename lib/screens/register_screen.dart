import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Tam özellikli Kayıt (Register) ekranı
/// - Form + alan doğrulayıcıları
/// - İsim/Soyisim & Telefon numarası alanları
/// - Parola güç göstergesi
/// - KVKK/Gizlilik kutucuğu
/// - Gelişmiş hata mesajları (TR)
/// - Google tek‑tıkla sosyal kayıt
/// - Tam ekran yükleniyor overlay
/// - Erişilebilirlik & küçük ekran desteği
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  ////////////////////////////// FORM KONTROL //////////////////////////////
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureAll = true;
  bool _acceptedTerms = false;
  String? _errorMessage;
  String _strengthLabel = '';

  ////////////////////////////// LIFE CYCLE //////////////////////////////
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  ////////////////////////////// UI HELPERS //////////////////////////////
  String _passwordStrength(String value) {
    if (value.length < 6) return 'Zayıf';
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasNumber = RegExp(r'\d').hasMatch(value);
    final hasSpecial = RegExp(r'[!@#\\$&*~]').hasMatch(value);
    final score = [hasLetter, hasNumber, hasSpecial].where((e) => e).length;
    return score == 3 ? 'Güçlü' : 'Orta';
  }

  String _firebaseErrorToTR(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Bu e‑posta zaten kullanımda.';
      case 'weak-password':
        return 'Parola çok zayıf. En az 6 karakter olmalı.';
      case 'invalid-email':
        return 'Geçerli bir e‑posta adresi girin.';
      default:
        return 'Beklenmedik bir hata oluştu.';
    }
  }

  ////////////////////////////// AUTH //////////////////////////////
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(() => _errorMessage = 'Lütfen şartları kabul edin.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // E‑posta & parola ile kayıt
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Görünür ismi güncelle
      await credential.user!.updateDisplayName(_nameController.text.trim());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt başarılı!')),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _firebaseErrorToTR(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // Kullanıcı geri döndü
        setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (context.mounted) {
        Navigator.pop(context);
      }
    } on Exception catch (_) {
      setState(() => _errorMessage = 'Google giriş başarısız.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  ////////////////////////////// BUILD //////////////////////////////
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Baylan Sayaç',
                        style: Theme.of(context).textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    ////////////////////// İSİM //////////////////////
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Ad Soyad',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => v == null || v.trim().length < 3
                          ? 'Lütfen adınızı girin'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    ////////////////////// TELEFON //////////////////////
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        hintText: 'Telefon (isteğe bağlı)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    ////////////////////// E‑POSTA //////////////////////
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        hintText: 'E‑posta',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'E‑posta gerekli.';
                        final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                        return emailRegex.hasMatch(v) ? null : 'Geçersiz e‑posta.';
                      },
                    ),
                    const SizedBox(height: 16),

                    ////////////////////// PAROLA //////////////////////
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscureAll,
                      decoration: InputDecoration(
                        hintText: 'Parola',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureAll
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(() => _obscureAll = !_obscureAll),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (v) => setState(() => _strengthLabel = _passwordStrength(v)),
                      validator: (v) => v == null || v.length < 6
                          ? 'Parola en az 6 karakter olmalı'
                          : null,
                    ),
                    if (_strengthLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Parola Gücü: $_strengthLabel',
                        style: TextStyle(
                          color: _strengthLabel == 'Güçlü'
                              ? Colors.green
                              : _strengthLabel == 'Orta'
                              ? Colors.orange
                              : Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    ////////////////////// PAROLA TEKRAR //////////////////////
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureAll,
                      decoration: InputDecoration(
                        hintText: 'Parola (Tekrar)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureAll
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(() => _obscureAll = !_obscureAll),
                        ),
                      ),
                      validator: (v) => v != _passwordController.text
                          ? 'Parolalar eşleşmiyor.'
                          : null,
                    ),

                    const SizedBox(height: 24),

                    ////////////////////// ŞARTLAR //////////////////////
                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Kullanım Şartları ve Gizlilik Politikasını okudum.'),
                    ),

                    const SizedBox(height: 16),

                    ////////////////////// KAYIT BUTONU //////////////////////
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        child: const Text('Kayıt Ol'),
                      ),
                    ),

                    ////////////////////// HATA MESAJI //////////////////////
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ],

                    const SizedBox(height: 24),

                    ////////////////////// SOSYAL GİRİŞ //////////////////////
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade400)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('veya'),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade400)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Image.asset('assets/google_logo.png', width: 20, height: 20),
                        label: const Text('Google ile Kayıt Ol'),
                        onPressed: _isLoading ? null : _signInWithGoogle,
                      ),
                    ),

                    const SizedBox(height: 24),

                    ////////////////////// GİRİŞ EKRANINA DÖN //////////////////////
                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        child: const Text(
                          'Zaten hesabın var mı? Giriş Yap',
                          style: TextStyle(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          ////////////////////// YÜKLENİYOR MODAL //////////////////////
          if (_isLoading) ...[
            const ModalBarrier(dismissible: false, color: Colors.black45),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
