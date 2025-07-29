# Sayaç Fatura Takip Uygulaması

**Flutter ve Firebase ile geliştirilmiş, Google ML Kit destekli modern bir sayaç okuma ve fatura takip mobil uygulaması.**

Bu proje, elektrik ve su gibi faturaların takibini kolaylaştırmak amacıyla geliştirilmiştir. Kullanıcılar, faturalarının fotoğraflarını çekerek Optik Karakter Tanıma (OCR) teknolojisi ile verileri otomatik olarak uygulamaya aktarabilir veya manuel olarak giriş yapabilirler.

---

## 📱 Ekran Görüntüleri & Demo



| Giriş Ekranı | Ana Ekran | Fatura Tarama |
| :---: | :---: | :---: |
| <img src="" width="200"/> | <img src="" width="200"/> | <img src="" width="200"/> |

---

## ✨ Özellikler

* **Google ML Kit ile Fatura Tarama:** Cihazın kamerası veya galerisi kullanılarak faturalar taranır ve üzerindeki metinler otomatik olarak okunur.
* **Akıllı Metin Ayrıştırma:** Taranan metinler, İZSU ve GEDİZ gibi farklı fatura formatlarına özel olarak hazırlanan kurallarla analiz edilerek Tesisat Numarası, Fatura Tutarı, Son Ödeme Tarihi gibi önemli veriler otomatik olarak ilgili alanlara doldurulur.
* **Firebase ile Güvenli Kullanıcı Yönetimi:**
    * E-posta ve Parola ile kayıt olma ve giriş yapma.
    * Google ile tek tıkla sosyal giriş yapma.
* **Bulutta Veri Saklama:**
    * Tüm okuma ve fatura verileri, her kullanıcı için özel olarak **Firestore Veritabanı**'nda saklanır.
    * Taranan fatura görselleri, güvenli bir şekilde **Firebase Storage**'da depolanır.
* **Geçmiş Kayıtlar:**
    * Tüm geçmiş fatura kayıtları listelenir.
    * Sayaç adı veya tesisat numarasına göre arama yapma.
    * Fatura tipine (kWh, m³) ve tarih aralığına göre filtreleme.
* **İnteraktif Grafikler:** Aylık toplam fatura harcamalarını gösteren dinamik ve anlaşılır grafikler (`fl_chart` paketi ile).
* **Modern ve Kurumsal Arayüz:** Baylan Water Meters kurumsal kimliğinden ilham alan, Material 3 standartlarına uygun, temiz ve profesyonel bir tema.

---

## 🚀 Kullanılan Teknolojiler

* **Framework:** Flutter
* **Dil:** Dart
* **Backend & Veritabanı:** Firebase
    * **Authentication:** Güvenli kullanıcı yönetimi.
    * **Firestore:** NoSQL veritabanı.
    * **Storage:** Fatura görselleri için dosya depolama.
    * **App Check:** Uygulama güvenliği ve sahteciliği önleme.
* **Optik Karakter Tanıma (OCR):** Google ML Kit
    * `google_mlkit_text_recognition`
    * `google_mlkit_document_scanner`
* **Grafikler:** `fl_chart`
* **Durum Yönetimi (State Management):** Dahili (`StatefulWidget`, `setState`)
* **Diğer Önemli Paketler:**
    * `permission_handler`: Cihaz izinlerini yönetmek için.
    * `path_provider`: Dosya yollarını yönetmek için.
    * `intl`: Tarih ve sayı formatlaması için.
    * `geolocator`: Konum bilgisi almak için.

---

## 🔧 Kurulum ve Başlatma

Bu projeyi yerel makinenizde çalıştırmak için aşağıdaki adımları izleyin:

1.  **Ön Gereksinimler:**
    * [Flutter SDK](https://flutter.dev/docs/get-started/install)'nın kurulu olduğundan emin olun.
    * Bir kod editörü (VS Code, Android Studio vb.).

2.  **Projeyi Klonlayın:**
    ```bash
    git clone [PROJENİZİN_GITHUB_LİNKİ]
    cd sayac-fatura-app
    ```

3.  **Firebase Kurulumu:**
    * Firebase'de yeni bir proje oluşturun.
    * Projenize bir **Android uygulaması** ekleyin. `com.example.sayacfaturapp` paket adını kullanabilirsiniz.
    * **Authentication**'ı aktif edin ve "E-posta/Parola" ile "Google" sağlayıcılarını etkinleştirin.
    * **Firestore Database**'i test modunda oluşturun.
    * **Storage**'ı oluşturun ve **Rules** (Kurallar) sekmesini aşağıdaki gibi güncelleyin:
        ```javascript
        rules_version = '2';
        service firebase.storage {
          match /b/{bucket}/o {
            match /invoice_images/{userId}/{allPaths=**} {
              allow read, write: if request.auth != null && request.auth.uid == userId;
            }
          }
        }
        ```
    * **App Check**'i aktif edin, uygulamanızı kaydedin (Play Integrity) ve geliştirme için **debug SHA-256 anahtarınızı** ekleyin.
    * Proje ayarlarından `google-services.json` dosyasını indirin ve projenizin `android/app/` klasörüne yerleştirin.

4.  **Paketleri Yükleyin:**
    ```bash
    flutter pub get
    ```

5.  **Uygulamayı Çalıştırın:**
    ```bash
    flutter run
    ```

---