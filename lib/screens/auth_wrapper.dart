// lib/screens/auth_wrapper.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sayacfaturapp/screens/home_screen.dart';
import 'package:sayacfaturapp/screens/login_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Firebase'deki anlık kimlik doğrulama durumunu dinle
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Bağlantı bekleniyorsa, yükleniyor ekranı göster
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Eğer kullanıcı verisi varsa (giriş yapmışsa), ana ekranı göster
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // Eğer kullanıcı verisi yoksa (giriş yapmamışsa), giriş ekranını göster
        return const LoginScreen();
      },
    );
  }
}