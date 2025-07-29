// lib/themes/custom_components.dart

import 'package:flutter/material.dart';

/// Uygulama genelinde tutarlı bir görünüm için kullanılacak,
/// özel olarak stillendirilmiş Card widget'ı.
class AppStyledCard extends StatelessWidget {
  // Bu kartın içine yerleştirilecek olan widget (içerik).
  final Widget child;

  const AppStyledCard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.white,
      // Material 3'te kartların üzerine hafif bir renk tonu eklenmesini engeller.
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: child,
    );
  }
}