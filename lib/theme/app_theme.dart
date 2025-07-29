import 'package:flutter/material.dart';

class AppTheme {
  // Ana marka renklerini burada tanımlayalım
  static const Color _primaryColor = Color(0xFF0059B2);
  static const Color _secondaryColor = Color(0xFF00C2FF);
  static const Color _backgroundColor = Color(0xFFF5F9FF);
  static const Color _textColor = Color(0xFF1E2A3B);

  // Açık tema (Light Theme)
  static ThemeData lightTheme = ThemeData(
    // === 1. Material 3 ve Ana Renk Şeması ===
    useMaterial3: true,
    fontFamily: 'Poppins',
    primaryColor: _primaryColor,
    scaffoldBackgroundColor: _backgroundColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primaryColor,
      primary: _primaryColor,
      secondary: _secondaryColor,
      background: _backgroundColor,
      surface: Colors.white,
      onPrimary: Colors.white,
      onBackground: _textColor,
      onSurface: _textColor,
      error: Colors.redAccent,
    ),

    // === 2. Metin Stilleri (Typography) ===
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.bold, color: _textColor, fontFamily: 'Poppins'),
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _textColor, fontFamily: 'Poppins'),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: _textColor, fontFamily: 'Poppins'),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _textColor, fontFamily: 'Poppins'),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor, fontFamily: 'Poppins'),
      bodyLarge: TextStyle(fontSize: 16, color: _textColor, fontFamily: 'Poppins'),
      bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C), fontFamily: 'Poppins'),
      bodySmall: TextStyle(fontSize: 12, color: Color(0xFF5C5C5C), fontFamily: 'Poppins'),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins'),



    ),

    // === 3. Bileşen Stilleri (Component Themes) ===

    // AppBar Teması
    appBarTheme: const AppBarTheme(
      backgroundColor: _backgroundColor,
      foregroundColor: _textColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _textColor,
        fontFamily: 'Poppins',
      ),
    ),

    // Buton Teması
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
      ),
    ),
    // Outlined Button Teması
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _textColor, // Buton üzerindeki yazı/ikon rengi
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.grey.shade300), // Kenar çizgisi rengi
      ),
    ),

// Text Button Teması
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _primaryColor, // Yazı rengi
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline, // Altı çizili stil
        ),
      ),
    ),

    // Giriş Alanı (TextField) Teması
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: _backgroundColor,
      selectedColor: _primaryColor,
      labelStyle: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
      secondaryLabelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: Colors.grey.shade300),
      showCheckmark: false,
    ),

    // Checkbox (Onay Kutusu) Teması
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      checkColor: MaterialStateProperty.all(Colors.white), // Tik işaretinin rengi
      fillColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return _primaryColor; // Seçiliyken ana renk
        }
        return Colors.grey.shade300; // Seçili değilken gri
      }),
    ),

// Divider (Ayırıcı Çizgi) Teması
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade300,
      thickness: 1,
    ),



  );
}