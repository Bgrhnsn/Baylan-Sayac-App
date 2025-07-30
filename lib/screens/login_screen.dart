import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:sayacfaturapp/screens/register_screen.dart';

// GÜNCELLEME: home_screen.dart import'u artık gerekli değil.
// import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  String _firebaseErrorToTR(String code) {
    switch (code) {
    // GÜVENLİK GÜNCELLEMESİ: Tüm hatalı giriş denemeleri tek bir mesajda birleştirildi.
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta veya parola hatalı.';

      case 'invalid-email':
        return 'Geçerli bir e-posta adresi girin.';
      case 'user-disabled':
        return 'Bu kullanıcı hesabı devre dışı bırakılmış.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin.';
      default:
        return 'Beklenmedik bir hata oluştu. Lütfen tekrar deneyin.';
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // Manuel yönlendirme kaldırıldı. AuthWrapper bunu otomatik yapacak.
    } on FirebaseAuthException catch (e) {
      print('YAKALANAN FIREBASE HATA KODU: ${e.code}');
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
      // Manuel yönlendirme (pop) kaldırıldı. AuthWrapper bunu otomatik yapacak.
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Google ile giriş başarısız oldu.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Temadan renkleri ve stilleri alıyoruz.
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(//formun taşmasını engellemek için
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, // Butonları tam genişlik yapar
                  children: [
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'Sayaç Fatura Takip',
                        style: textTheme.headlineLarge?.copyWith(color: colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Hoş geldiniz!',
                        style: textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(height: 48),

                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'E-posta', // HintText yerine LabelText daha şık durur
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
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Parola',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Parola alanı boş bırakılamaz.' : null,
                      onFieldSubmitted: (_) => _signIn(), // Enter'a basınca giriş yap
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      child: const Text('Giriş Yap'),
                    ),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Center(
                          // GÜNCELLEME: Hata mesajı stilini temadan (colorScheme.error) alıyor.
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
                      label: const Text('Google ile Giriş Yap'),
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      // GÜNCELLEME: Stil, merkezi temadan (OutlinedButtonTheme) geldiği için kaldırıldı.
                    ),

                    const SizedBox(height: 24),
                    Center(
                      child: TextButton(
                    onPressed: _isLoading
                    ? null
        : () {
    Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
    },
    child: const Text('Hesabın yok mu? Kayıt Ol'),
    ),
                        // GÜNCELLEME: Stil, merkezi temadan (TextButtonTheme) geldiği için kaldırıldı.
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