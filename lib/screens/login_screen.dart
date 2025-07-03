import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Tam özellikli Giriş (Login) ekranı
/// - Form + alan doğrulayıcıları
/// - Parola gizle/göster ikonu
/// - Gelişmiş hata mesajları (TR)
/// - Google tek‑tıkla sosyal giriş (PNG ikon)
/// - Tam ekran yükleniyor overlay
/// - Erişilebilirlik & küçük ekran desteği
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  ////////////////////////////// FORM KONTROL //////////////////////////////
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  ////////////////////////////// UI HELPERS //////////////////////////////
  String _firebaseErrorToTR(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Kullanıcı bulunamadı.';
      case 'wrong-password':
        return 'Parola hatalı.';
      case 'invalid-email':
        return 'Geçerli bir e‑posta adresi girin.';
      default:
        return 'Beklenmedik bir hata oluştu.';
    }
  }

  ////////////////////////////// AUTH //////////////////////////////
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Giriş başarılı!')),
        );
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
        setState(() => _isLoading = false);
        return; // kullanıcı iptal etti
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
    } on Exception {
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
                    const SizedBox(height: 40),
                    Center(
                      child: Text('Baylan Sayaç',
                          style: Theme.of(context).textTheme.headlineLarge),
                    ),
                    const SizedBox(height: 32),

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
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Parola',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Parola gerekli.' : null,
                    ),
                    const SizedBox(height: 24),

                    ////////////////////// GİRİŞ BUTONU //////////////////////
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        child: const Text('Giriş Yap'),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Divider(thickness: 1)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('veya'),
                        ),
                        Expanded(child: Divider(thickness: 1)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    ////////////////////// GOOGLE İLE GİRİŞ //////////////////////
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Image.asset('assets/google_logo.png', width: 20, height: 20),
                        label: const Text('Google ile Giriş Yap'),
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : () => Navigator.pushNamed(context, '/register'),
                        child: const Text(
                          'Hesabın yok mu? Kayıt Ol',
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
