# Karlı Gece

TL vadesiz / gecelik **mevduat** hesapları için net faiz hesaplayan iOS uygulaması. Bankaların koşullarını (oran, kademe, vadesiz tutma şartı, stopaj) siz tanımlarsınız. Uygulama da gecelik net kazancı, valör kurallı bileşiklemeyi, bankalar arasındaki farkı ve tutarın bankalara en kârlı nasıl bölüneceğini hesaplar. Bankalardaki gerçek bakiyelerinizi de her açılışta faiziyle günceller.

> Hiçbir banka kuralı ya da vergi oranı koda gömülü değildir. Stopaj %17,5 ile ön dolu gelir ama bu oran **temsilîdir**; kullanmadan önce yürürlükteki oranı kontrol edin. Uygulama finansal tavsiye vermez.

## Sekmeler

| Sekme | Ne yapar |
|---|---|
| **Özet** | Seçili banka için başlangıç–bitiş tarihleri arasındaki brüt faizi, stopajı, net kazancı ve vade sonu bakiyesini gösterir. |
| **Düzenle** | Bakiye, stopaj ve banka koşullarını tanımlar: oran, brüt/net taban, vadesiz şartı (yok / yüzde / sabit / kademeli), asgari bakiye, faize tabi azami tutar, EFT ücreti. |
| **Karşılaştır** | 2 veya 3 bankayı ortak bir tutarla yan yana koyar ve 1 / 7 / 30 / 90 / 365 günlük net kazancı gösterir. |
| **Max** | Tutarı kayıtlı bankalara, N günün sonundaki toplam net kazanç (EFT ücretleri düşülmüş) en yüksek olacak şekilde böler. Hesaplanan planlar tarihleriyle geçmişe kaydedilir. |
| **Profil** | Menü listesi: kişisel bilgiler (ad, soyad), **Bakiyelerim**, görünüm (Sistem / Açık / Koyu), dil (Türkçe / English) ve Hakkında. Bakiyelerim, bankalardaki gerçek bakiyeleri tutar ve uygulama her açıldığında valörü gelen net faizi bakiyenin üzerine ekler. |

## Hesaplama kuralları

- **Kademe sınırı dışlayıcıdır:** bakiye `< üst sınır` ise o kademe geçerlidir. Örneğin tam 50.000 ₺ bir üst kademeye düşer.
- **Valör ve bileşikleme:** Hafta içi her gecenin net kazancı ertesi gün 00:00'da bakiyeye eklenir ve bileşiklenir. Cuma, Cumartesi ve Pazar geceleri aynı bakiye üzerinden işler ve toplamı Pazartesi 00:00'da eklenir; hafta sonu kendi içinde bileşiklenmez. Bitiş tarihi hafta sonuna denk gelirse Pazartesi'ye kaydırılır. Tatil takvimi yoktur.
- **Efektif oran** her zaman 365 takvim günüyle hesaplanır. Böylece gün sayımı tabanı farklı bankalar karşılaştırılabilir.
- **Max planı** kademeli bir bankada N. günün sonunda üst kademeye geçmez. Tutar, sınırın altında "1 günlük net faizin %10'u" kadar pay bırakacak şekilde seçilir. Hiçbir bankaya kazanç katmayan para "Dağıtılmayan" olarak kalır.
- **EFT ücreti** yalnız Max planında kullanılır: para ayrılan her bankanın kazancından bir kez düşülür. Bankanın kendi karı (N günlük net kazanç − EFT) 20 ₺'yi geçmiyorsa o bankaya para ayrılmaz.
- **Bakiyelerim** her kaydı Düzenle'deki bir bankaya bağlar (her bankada bir kayıt). Uygulama açılışta ve öne geldiğinde, son valör gününden bu yana valörü gelen geceleri o bankanın koşulları ve stopajla bileşikler ve net faizi bakiyeye kalıcı olarak ekler. Kural Özet'le aynıdır: hafta içi kazanç ertesi gün eklenir, Cuma–Pazar kazancı Pazartesi eklenir. Hafta sonu bakiye değişmez, biriken tutar gösterilir. Her valör günü bir hareket olarak listelenir. Aynı gün tekrar açmak bir şey eklemez. Banka Düzenle'den silinirse kayıt durur ama faiz işlemez. Bakiye elle değiştirilirse yeni tutar o gün itibarıyla geçerli olur.
- Oturum (bakiye, stopaj, bankalar, seçili banka, sekme, Max geçmişi, profil, görünüm, dil, Bakiyelerim) `UserDefaults`'a JSON olarak kaydedilir.

## Mimari

```
InterestCalculator/
├── Engine/        Saf, deterministik hesap motoru (yalnız Foundation)
├── Parsing/       Türkçe ondalık girdi ayrıştırma (yalnız Foundation)
├── State/         AppState, taslaklar (Codable), takvim, Karşılaştır/Max hesaplayıcıları, Bakiyelerim defteri, kalıcılık
├── Presentation/  Biçimlendirme, sonuç metinleri, dil çözümleme, tema
└── Features/      SwiftUI ekranları (Summary, Editor, Compare, Max, Profile, Root)
```

- `InterestEngine.calculate` tek bir gecenin hesabıdır ve tek doğruluk kaynağıdır. Toplam bir fonksiyondur: throw etmez, `fatalError` atmaz, NaN üretmez. `CompoundingEngine.project` her geceyi bu fonksiyonla hesaplayıp bileşikler.
- Motor `Date`, `Locale` ya da `NumberFormatter` kullanmaz. Gerçek tarih ile hafta günü arasındaki eşleme State katmanındaki `AccrualCalendar`'dadır.
- Bakiyelerim günleri `Date` olarak değil `CalendarDay` (2001-01-01'den bu yana geçen gün sayısı) olarak saklar. Cihaz saat dilimi değişse de kayıtlı gün kaymaz ve aynı gece iki kez işletilmez. İşletme `HoldingLedger`'dadır; her valör gününün kazancı `CompoundingEngine.project` ile hesaplanır.
- Para tutarları `Decimal` ile tutulur. Yuvarlama `RoundingPolicy` ile merkezi olarak yapılır.
- **Dil:** Metinler kodda Türkçe yazılır (kaynak dil); İngilizceleri `Localizable.xcstrings`'tedir. Dil cihazdan bağımsız seçilir (varsayılan Türkçe). Kök görünüm seçimi `\.locale` ortamına verir; SwiftUI'ye literal verilen metinler çeviriyi buradan bulur. Kodda `String` olarak kurulan metinler `Locale.localized(_:)` ile çözülür, çünkü `String(localized:)` dili cihazdan seçer. Sayı ve tarihler seçilen dil ile cihaz bölgesinin birleşimiyle biçimlenir (Türkiye'de English → `en_TR`).
- **Katman sınırı:** `Engine/` ve `Parsing/` SwiftUI veya UIKit import etmez. Bu kuralı [`scripts/check-engine-purity.sh`](scripts/check-engine-purity.sh) denetler.

## Gereksinimler

- Xcode 27 (iOS 27 SDK)
- Deployment target: iOS 18, iPhone ve iPad
- Harici bağımlılık yoktur

## Derleme ve test

Projeyi Xcode'da açın ve `InterestCalculator` şemasını çalıştırın:

```bash
open InterestCalculator.xcodeproj
```

Komut satırından testleri çalıştırmak için simülatör sürümünü sabitleyin. Aksi halde `xcodebuild` en yeni runtime'ı seçer:

```bash
xcodebuild test -project InterestCalculator.xcodeproj -scheme InterestCalculator -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```

Birim testleri (`InterestCalculatorTests`) Swift Testing ile yazılmıştır. Motor sonuçları golden testlerle sabitlenmiştir. UI testleri (`InterestCalculatorUITests`) uygulamayı `-uitesting` argümanıyla başlatır. Bu argümanla kalıcılık atlanır ve her test temiz durumdan başlar.

### Pre-commit hook

Katman sınırı kontrolünü her commit'ten önce otomatik çalıştırmak için:

```bash
printf '#!/bin/sh\nexec "$(git rev-parse --show-toplevel)/scripts/check-engine-purity.sh"\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```
