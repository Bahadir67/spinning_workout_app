# Strava Entegrasyonu Kurulumu

APK artık Strava entegrasyonunu destekliyor! Aktivitelerinizi Strava'ya yüklemek için aşağıdaki adımları izleyin:

## 1. Strava API Anahtarlarını Alın

1. **Strava Developer Portal'a gidin**: https://www.strava.com/settings/api
2. **"Create & Manage Your App"** butonuna tıklayın
3. Yeni bir uygulama oluşturun:
   - **Application Name**: Spinning Workout App
   - **Category**: Training
   - **Club**: (boş bırakabilirsiniz)
   - **Website**: http://localhost (veya kendi siteniz)
   - **Authorization Callback Domain**: `spinworkout`
   - **Application Description**: Indoor spinning workout tracker

4. Uygulamanız oluşturulduktan sonra şu bilgileri not edin:
   - **Client ID** (örnek: 123456)
   - **Client Secret** (örnek: abc123def456...)

## 2. Uygulamada API Anahtarlarını Güncelleyin

`lib/services/strava_service.dart` dosyasında 13-14. satırlarda:

```dart
static const String CLIENT_ID = 'YOUR_CLIENT_ID';        // ← Buraya Client ID'nizi yazın
static const String CLIENT_SECRET = 'YOUR_CLIENT_SECRET'; // ← Buraya Client Secret'ınızı yazın
```

**Örnek:**
```dart
static const String CLIENT_ID = '123456';
static const String CLIENT_SECRET = 'abc123def456789xyz';
```

## 3. Yeniden Derleyin

```bash
flutter build apk --release --target=lib/main.dart
```

## 4. Kullanım

### İlk Giriş:
1. Antrenmanı bitirin
2. Özet ekranında **"Strava'ya Yükle"** butonuna tıklayın
3. "Giriş Yap" butonuna basın
4. Tarayıcı açılacak - Strava hesabınızla giriş yapın
5. "Authorize" butonuna tıklayın
6. Uygulama otomatik olarak geri dönecek

### Sonraki Kullanımlar:
- Özet ekranında **"Strava'ya Yükle"** butonuna tıklamanız yeterli
- Aktivite otomatik olarak Strava'ya yüklenecek
- Token'lar cihazda güvenle saklanıyor

## Özellikler

✅ OAuth 2.0 ile güvenli giriş
✅ FIT dosya formatı (Garmin/Strava uyumlu)
✅ Kalp atışı, güç ve kadans verileri
✅ TSS, IF, NP metrikleri
✅ Otomatik token yenileme
✅ "Indoor Cycling" olarak işaretlenir

## Sorun Giderme

**Problem**: "Not authenticated" hatası alıyorum
**Çözüm**: Yeniden giriş yapın - token'lar süresi dolmuş olabilir

**Problem**: Upload başarısız oluyor
**Çözüm**:
- İnternet bağlantınızı kontrol edin
- CLIENT_ID ve CLIENT_SECRET'ın doğru olduğundan emin olun
- Strava Developer Portal'da uygulamanızın aktif olduğunu kontrol edin

**Problem**: Tarayıcı açılmıyor
**Çözüm**: url_launcher izinlerini kontrol edin

## Güvenlik Notu

⚠️ **ÖNEMLİ**: CLIENT_SECRET'ı GitHub gibi public yerlerde paylaşmayın!
- Sadece kendi kullanımınız için compile edin
- Google Play'e yüklerseniz, environment variables kullanın

## APK Konumu

Derlenmiş APK: `build/app/outputs/flutter-apk/app-release.apk`

---

**Not**: Şu anda CLIENT_ID ve CLIENT_SECRET placeholder değerlerde. Yukarıdaki adımları takip ederek kendi anahtarlarınızı ekleyin.
