import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white), // Geri okunu beyaz yapar
      ),

      backgroundColor: Colors.black,
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),

        // Minimum ölçek ayarı. Görüntünün ekrana sığacak boyuttan
        // daha fazla küçültülmesini engeller.
        minScale: PhotoViewComputedScale.contained,

        //  Maksimum ölçek ayarı. Çok fazla yakınlaştırmayı sınırlar.
        maxScale: PhotoViewComputedScale.covered * 2.5,

        //  Başlangıç ölçeği. Görüntünün ekrana sığarak başlamasını sağlar.
        initialScale: PhotoViewComputedScale.contained,

        //  Hero animasyonu için tag. Detay ekranındakiyle aynı olmalı.
        heroAttributes: PhotoViewHeroAttributes(tag: imageUrl),

        loadingBuilder: (context, event) => const Center(
          // Yükleme animasyonunun siyah arka planda görünmesi için rengi beyaz yapıldı.
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.error, color: Colors.red),
        ),
      ),
    );
  }
}
