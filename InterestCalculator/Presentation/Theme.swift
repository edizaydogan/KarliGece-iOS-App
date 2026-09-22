//
//  Theme.swift
//  InterestCalculator
//
//  Tek gradyan + tema notları. Üç ekranlık uygulama için TEK dosya.
//
//  NOT: Renk token'larının Swift sembolleri —  `Color.snowfield`,
//  `.foregroundStyle(.slate)` (ShapeStyle) ve `Color(.snowfield)` (ColorResource)—
//  `Assets.xcassets/Colors/` altındaki setlerden OTOMATİK üretilir
//  (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES). Bu yüzden
//  burada elle `extension Color` / `extension ShapeStyle where Self == Color`
//  YAZILMAZ; yazılırsa "invalid redeclaration" hatası verir. Yalnız asset karşılığı
//  OLMAYAN türevler (gradyan gibi) bu dosyada tanımlanır.
//
//  "Provides Namespace" Colors klasöründe İŞARETLİ DEĞİL; sembol adları düz
//  (`.snowfield`), `.colors.snowfield` değil.
//

import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    /// Gece göğü gradyanı — YALNIZ Tab 1'in zemininde kullanılır.
    /// Kart yüzeyleri gradyan ALMAZ; her yerde olursa marka anı gürültüye döner.
    static var nightSky: LinearGradient {
        LinearGradient(
            colors: [.midnightTop, .midnightBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
