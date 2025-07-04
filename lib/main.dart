import 'package:flutter/material.dart';

// Paket importları
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
// YENİ: Lokalizasyon delegeleri için gerekli import
import 'package:flutter_localizations/flutter_localizations.dart';

// Proje importları
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/new_reading_screen.dart';
import 'screens/register_screen.dart';
import 'screens/history_screen.dart';

void main() async {
  // Flutter binding'lerinin uygulama çalışmadan önce hazır olduğundan emin ol.
  WidgetsFlutterBinding.ensureInitialized();

  // Türkçe tarih formatlamasını başlat.
  await initializeDateFormatting('tr_TR', null);

  // Firebase servisini başlat.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sayaç Fatura Uygulaması',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,             // Alt bar arka planı
          selectedItemColor: Colors.blueAccent,      // Seçili ikon ve etiket
          unselectedItemColor: Colors.grey,          // Diğer ikonlar
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      // HATA ÇÖZÜMÜ: Lokalizasyon delegelerini ve desteklenen dilleri ekle.
      // Bu delegeler, takvim gibi Material bileşenlerinin Türkçeleştirilmesini sağlar.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'), // Türkçe
        // İleride başka diller eklemek isterseniz buraya ekleyebilirsiniz.
        // Locale('en', 'US'), // İngilizce
      ],

      // Uygulamanın başlayacağı ilk rotayı belirtir.
      initialRoute: '/login',

      // Uygulama içi yönlendirme rotaları
      routes: {
        '/login'   : (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home'    : (_) => const HomeScreen(),
        '/newReading': (_) => const NewReadingScreen(),
        '/history': (_) => const HistoryScreen(),
      },
    );
  }
}
