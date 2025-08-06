// lib/screens/auth_wrapper.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sayacfaturapp/screens/home_screen.dart';
import 'package:sayacfaturapp/screens/login_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Bağlantı bekleniyorsa
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // Hata durumu
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Bir hata oluştu: ${snapshot.error}')));
        }

        // Kullanıcı giriş yapmışsa
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // Giriş yapılmamışsa
        return const LoginScreen();
      },
    );
  }
}
