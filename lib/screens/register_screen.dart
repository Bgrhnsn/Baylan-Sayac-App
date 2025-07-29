import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Color _getStrengthColor(String strength) {
    switch (strength) {
      case 'Güçlü':
        return Colors.green;
      case 'Orta':
        return Colors.orange;
      case 'Zayıf':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _passwordStrength(String value) {
    if (value.isEmpty) return '';
    if (value.length < 6) return 'Zayıf';
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasNumber = RegExp(r'\d').hasMatch(value);
    final hasSpecial = RegExp(r'[!@#$&*~]').hasMatch(value);
    final score = [hasLetter, hasNumber, hasSpecial].where((e) => e).length;
    return score >= 2 ? 'Güçlü' : 'Orta';
  }

  String _firebaseErrorToTR(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Bu e-posta adresi zaten kullanımda.';
      case 'weak-password':
        return 'Parola çok zayıf. En az 6 karakter olmalı.';
      case 'invalid-email':
        return 'Geçerli bir e-posta adresi girin.';
      default:
        return 'Beklenmedik bir hata oluştu. Lütfen tekrar deneyin.';
    }
  }

  /// GÜNCELLEME: Kayıt sonrası geri bildirim ve yönlendirme eklendi.
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(() => _errorMessage = 'Lütfen kullanım şartlarını kabul edin.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      // 1. Kullanıcıyı Firebase Auth ile oluştur.
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // 2. Kullanıcının adını güncelle.
      await credential.user!.updateDisplayName(_nameController.text.trim());

      // 3. ÖNEMLİ: Kullanıcıyı hemen çıkış yaptırarak Auth sarmalayıcısının
      // ana ekrana yönlendirmesini engelle ve manuel giriş yapmasını sağla.
      await FirebaseAuth.instance.signOut();

      // 4. Başarı mesajı göster ve giriş ekranına dön.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesabınız başarıyla oluşturuldu! Lütfen giriş yapın.'),
            backgroundColor: Colors.green,
          ),
        );
        // Kayıt ekranını kapatarak bir önceki ekrana (Giriş) dön.
        Navigator.of(context).pop();
      }

    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _firebaseErrorToTR(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      // Google ile giriş yapıldığında AuthWrapper ana ekrana yönlendirecektir.
      // Bu yüzden burada manuel yönlendirme yok.
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Google ile giriş başarısız oldu.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Hesap Oluştur'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text(
                        'Bilgilerinizi Girin',
                        style: textTheme.headlineSmall?.copyWith(color: colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 32),

                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => v == null || v.trim().length < 3
                          ? 'Lütfen geçerli bir ad soyad girin.'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'E-posta',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'E-posta alanı boş bırakılamaz.';
                        final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                        return emailRegex.hasMatch(v) ? null : 'Lütfen geçerli bir e-posta adresi girin.';
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscureAll,
                      decoration: InputDecoration(
                        labelText: 'Parola',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureAll
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscureAll = !_obscureAll),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (v) => setState(() => _strengthLabel = _passwordStrength(v)),
                      validator: (v) => v == null || v.length < 6
                          ? 'Parola en az 6 karakter olmalı.'
                          : null,
                    ),
                    if (_strengthLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                        child: Text(
                          'Parola Gücü: $_strengthLabel',
                          style: textTheme.bodyMedium?.copyWith(
                            color: _getStrengthColor(_strengthLabel),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureAll,
                      decoration: const InputDecoration(
                        labelText: 'Parola (Tekrar)',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => v != _passwordController.text
                          ? 'Parolalar eşleşmiyor.'
                          : null,
                    ),
                    const SizedBox(height: 24),

                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'Kullanım Şartları ve Gizlilik Politikasını okudum, kabul ediyorum.',
                        style: textTheme.bodyMedium,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      child: const Text('Kayıt Ol'),
                    ),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Center(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('veya', style: TextStyle(color: Colors.grey)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),

                    OutlinedButton.icon(
                      icon: Image.asset('assets/google_logo.png', width: 20, height: 20),
                      label: const Text('Google ile Kayıt Ol'),
                      onPressed: _isLoading ? null : _signInWithGoogle,
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Zaten hesabın var mı? Giriş Yap'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isLoading)
            const ModalBarrier(dismissible: false, color: Colors.black45),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
