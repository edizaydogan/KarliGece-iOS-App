# Karlı Gece

TL vadesiz / gecelik **mevduat** hesapları için net faiz hesaplayan iOS uygulaması. Bankaların koşullarını (oran, kademe, vadesiz tutma şartı, stopaj) siz tanımlarsınız. Uygulama da gecelik net kazancı, valör kurallı bileşiklemeyi, bankalar arasındaki farkı ve tutarın bankalara en kârlı nasıl bölüneceğini hesaplar.

> Hiçbir banka kuralı ya da vergi oranı koda gömülü değildir. Stopaj %17,5 ile ön dolu gelir ama bu oran **temsilîdir**; kullanmadan önce yürürlükteki oranı kontrol edin. Uygulama finansal tavsiye vermez.

## Sekmeler

| Sekme | Ne yapar |
|---|---|
| **Özet** | Seçili banka için başlangıç–bitiş tarihleri arasındaki brüt faizi, stopajı, net kazancı ve vade sonu bakiyesini gösterir. |
| **Düzenle** | Bakiye, stopaj ve banka koşullarını tanımlar: oran, brüt/net taban, vadesiz şartı (yok / yüzde / sabit / kademeli), asgari bakiye, faize tabi azami tutar. |
| **Karşılaştır** | 2 veya 3 bankayı ortak bir tutarla yan yana koyar ve 1 / 7 / 30 / 90 / 365 günlük net kazancı gösterir. |
| **Max** | Tutarı kayıtlı bankalara, N günün sonundaki toplam net kazanç en yüksek olacak şekilde böler. Hesaplanan planlar tarihleriyle geçmişe kaydedilir. |

## Hesaplama kuralları

- **Kademe sınırı dışlayıcıdır:** bakiye `< üst sınır` ise o kademe geçerlidir. Örneğin tam 50.000 ₺ bir üst kademeye düşer.
- **Valör ve bileşikleme:** Hafta içi her gecenin net kazancı ertesi gün 00:00'da bakiyeye eklenir ve bileşiklenir. Cuma, Cumartesi ve Pazar geceleri aynı bakiye üzerinden işler ve toplamı Pazartesi 00:00'da eklenir; hafta sonu kendi içinde bileşiklenmez. Bitiş tarihi hafta sonuna denk gelirse Pazartesi'ye kaydırılır. Tatil takvimi yoktur.
- **Efektif oran** her zaman 365 takvim günüyle hesaplanır. Böylece gün sayımı tabanı farklı bankalar karşılaştırılabilir.
- **Max planı** kademeli bir bankada N. günün sonunda üst kademeye geçmez. Tutar, sınırın altında "1 günlük net faizin %10'u" kadar pay bırakacak şekilde seçilir. Hiçbir bankaya kazanç katmayan para "Dağıtılmayan" olarak kalır.
- Oturum (bakiye, stopaj, bankalar, seçili banka, sekme, Max geçmişi) `UserDefaults`'a JSON olarak kaydedilir.

## Mimari

```
InterestCalculator/
├── Engine/        Saf, deterministik hesap motoru (yalnız Foundation)
├── Parsing/       Türkçe ondalık girdi ayrıştırma (yalnız Foundation)
├── State/         AppState, taslaklar (Codable), takvim, Karşılaştır/Max hesaplayıcıları, kalıcılık
├── Presentation/  Biçimlendirme, sonuç metinleri, tema
└── Features/      SwiftUI ekranları (Summary, Editor, Compare, Max, Root)
```

- `InterestEngine.calculate` tek bir gecenin hesabıdır ve tek doğruluk kaynağıdır. Toplam bir fonksiyondur: throw etmez, `fatalError` atmaz, NaN üretmez. `CompoundingEngine.project` her geceyi bu fonksiyonla hesaplayıp bileşikler.
- Motor `Date`, `Locale` ya da `NumberFormatter` kullanmaz. Gerçek tarih ile hafta günü arasındaki eşleme State katmanındaki `AccrualCalendar`'dadır.
- Para tutarları `Decimal` ile tutulur. Yuvarlama `RoundingPolicy` ile merkezi olarak yapılır.
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
