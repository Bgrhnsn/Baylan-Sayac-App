import 'package:flutter/material.dart';

// Paket importları
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// YENİ: Firebase App Check paketini import ediyoruz.
import 'package:firebase_app_check/firebase_app_check.dart';

// Proje importları
import 'firebase_options.dart';
import 'package:sayacfaturapp/screens/auth_wrapper.dart';

void main() async {
  // Flutter binding'lerinin uygulama çalışmadan önce hazır olduğundan emin oluyoruz.
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase servisini başlatıyoruz. Diğer Firebase işlemleri bundan sonra gelmeli.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // YENİ: Firebase App Check'i aktive ediyoruz.
  // Bu, Storage gibi servislere yetkili erişim için gereklidir.
  await FirebaseAppCheck.instance.activate(
    // Geliştirme ortamında test için debug provider kullanılır.
    // Uygulamanızı yayınlarken bu ayarı değiştirmeniz gerekecektir.
    androidProvider: AndroidProvider.debug,
  );

  // Türkçe tarih formatlamasını başlatıyoruz.
  await initializeDateFormatting('tr_TR', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sayaç Fatura Uygulaması',
      debugShowCheckedModeBanner: false,

      // GÜNCELLEME: Tema, daha modern ve tutarlı bir görünüm için Material 3 ve ColorScheme kullanacak şekilde güncellendi.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.indigoAccent,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.indigoAccent, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
        ),
      ),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
      ],

      // Başlangıç noktamız AuthWrapper.
      home: const AuthWrapper(),
    );
  }
}