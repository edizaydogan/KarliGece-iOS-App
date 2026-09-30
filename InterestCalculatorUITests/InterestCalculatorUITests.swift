//
//  InterestCalculatorUITests.swift
//  InterestCalculatorUITests
//
//  UI testleri "bağlantı kopmuş mu" sorusunu cevaplar, "sayı doğru mu" sorusunu
//  değil. Formatlanmış sayı string'i ASLA assert edilmez; iki ayrı identifier
//  (resultPlaceholder / netResultValue) kullanılır.
//

import XCTest

final class InterestCalculatorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Launch testleri her UI yapılandırmasında (yatay dahil) koşup cihazı yatay
        // bırakabilir; bu testler dikey düzen varsayar (Form satırları ekranda olmalı).
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Form'un alt sıralarındaki bir alandan (ör. oran) sonra klavye kapanırken
    /// Form ~0,1 sn yukarı sıçrayıp geri döner; XCUITest bu hareketi beklemez ve
    /// hemen dokunmak bir üst satıra düşer. Öğenin çerçevesi iki ardışık okumada
    /// aynı kalana dek bekler, sonra dokunur.
    @MainActor
    private func tapWhenSettled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        var frame = element.frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.15)
            let current = element.frame
            if current == frame { break }
            frame = current
        }
        element.tap()
    }

    @MainActor
    func testAllTabsOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: her test temiz durumdan başlar
        app.launch()

        app.tabBars.buttons["Özet"].tap()
        XCTAssertTrue(element(app, "summaryRoot").waitForExistence(timeout: 5))

        app.tabBars.buttons["Düzenle"].tap()
        XCTAssertTrue(element(app, "editorRoot").waitForExistence(timeout: 5))

        app.tabBars.buttons["Karşılaştır"].tap()
        XCTAssertTrue(element(app, "compareRoot").waitForExistence(timeout: 5))

        app.tabBars.buttons["Max"].tap()
        XCTAssertTrue(element(app, "maxRoot").waitForExistence(timeout: 5))
    }

    @MainActor
    func testEndToEndHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: her test temiz durumdan başlar
        app.launch()

        // Başlangıçta Tab 1 boş: sonuç yer tutucusu görünür.
        XCTAssertTrue(element(app, "resultPlaceholder").waitForExistence(timeout: 5))

        // Tab 2'de bakiye + oran gir.
        app.tabBars.buttons["Düzenle"].tap()

        let balance = app.textFields["balanceField"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        balance.tap()
        balance.typeText("100000")
        app.buttons["Bitti"].firstMatch.tap()

        let rate = app.textFields["rateField"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()
        rate.typeText("45")
        app.buttons["Bitti"].firstMatch.tap()

        // Tab 1'e dön: yer tutucu gitti, net sonuç geldi (değer assert EDİLMEZ).
        app.tabBars.buttons["Özet"].tap()
        XCTAssertTrue(element(app, "netResultValue").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "resultPlaceholder").exists)
    }

    @MainActor
    func testCompareShowsColumnsAfterSecondBank() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: tek boş bankayla başlar
        app.launch()

        // Tek banka: Karşılaştır boş durumu gösterir.
        app.tabBars.buttons["Karşılaştır"].tap()
        XCTAssertTrue(element(app, "compareEmptyState").waitForExistence(timeout: 5))

        // Düzenle'de bakiye + oran, sonra ikinci banka.
        app.tabBars.buttons["Düzenle"].tap()
        let balance = app.textFields["balanceField"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        balance.tap()
        balance.typeText("100000")
        app.buttons["Bitti"].firstMatch.tap()

        let rate = app.textFields["rateField"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()
        rate.typeText("45")
        app.buttons["Bitti"].firstMatch.tap()

        tapWhenSettled(app.buttons["Banka ekle"])
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()
        rate.typeText("40")
        app.buttons["Bitti"].firstMatch.tap()

        // Karşılaştır: iki sütun ve vade hücreleri geldi (değer assert EDİLMEZ).
        app.tabBars.buttons["Karşılaştır"].tap()
        XCTAssertTrue(element(app, "compareNet_1_0").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "compareNet_1_1").exists)
        XCTAssertTrue(element(app, "compareNet_365_1").exists)
        XCTAssertFalse(element(app, "compareEmptyState").exists)
    }

    /// Karşılaştır'ın tutarı Düzenle'den tohumlanır ama yereldir: değiştirmek
    /// Düzenle'yi değiştirmez. Değerler biçimle değil, birbirleriyle karşılaştırılır.
    @MainActor
    func testCompareBalanceDoesNotChangeEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: tek boş bankayla başlar
        app.launch()

        // Düzenle'de tutar, sonra ikinci banka (Karşılaştır sütunları için).
        app.tabBars.buttons["Düzenle"].tap()
        let editorBalance = app.textFields["balanceField"]
        XCTAssertTrue(editorBalance.waitForExistence(timeout: 5))
        editorBalance.tap()
        editorBalance.typeText("100000")
        app.buttons["Bitti"].firstMatch.tap()
        app.buttons["Banka ekle"].tap()
        let editorValue = try XCTUnwrap(editorBalance.value as? String)

        // Karşılaştır: tutar Düzenle'den tohumlandı.
        app.tabBars.buttons["Karşılaştır"].tap()
        let compareBalance = app.textFields["compareBalanceField"]
        XCTAssertTrue(compareBalance.waitForExistence(timeout: 5))
        XCTAssertEqual(compareBalance.value as? String, editorValue)

        // Karşılaştır'da tutarı silip yenisini yaz. Metin sağa yaslı: ortaya dokunmak
        // imleci başa koyar, silme işe yaramaz — imleç sona düşsün diye sağ uca dokun.
        compareBalance.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        compareBalance.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: editorValue.count))
        compareBalance.typeText("5000")
        app.buttons["Bitti"].firstMatch.tap()
        let compareValue = try XCTUnwrap(compareBalance.value as? String)
        XCTAssertNotEqual(compareValue, editorValue)

        // Düzenle'deki tutar değişmedi.
        app.tabBars.buttons["Düzenle"].tap()
        XCTAssertTrue(editorBalance.waitForExistence(timeout: 5))
        XCTAssertEqual(editorBalance.value as? String, editorValue)

        // Karşılaştır'a dönünce yeniden tohumlanmaz: yerel tutar korunur.
        app.tabBars.buttons["Karşılaştır"].tap()
        XCTAssertTrue(compareBalance.waitForExistence(timeout: 5))
        XCTAssertEqual(compareBalance.value as? String, compareValue)
    }

    /// Max'ın tutarı Düzenle'den tohumlanır ama yereldir (Karşılaştır ile aynı model).
    @MainActor
    func testMaxBalanceSeedsFromEditorButDoesNotWriteBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: tek boş bankayla başlar
        app.launch()

        app.tabBars.buttons["Düzenle"].tap()
        let editorBalance = app.textFields["balanceField"]
        XCTAssertTrue(editorBalance.waitForExistence(timeout: 5))
        editorBalance.tap()
        editorBalance.typeText("100000")
        app.buttons["Bitti"].firstMatch.tap()
        let editorValue = try XCTUnwrap(editorBalance.value as? String)

        // Max: tutar Düzenle'den tohumlandı.
        app.tabBars.buttons["Max"].tap()
        let maxBalance = app.textFields["maxBalanceField"]
        XCTAssertTrue(maxBalance.waitForExistence(timeout: 5))
        XCTAssertEqual(maxBalance.value as? String, editorValue)

        // Max'ta tutarı değiştir (imleç sona düşsün diye sağ uca dokunulur).
        maxBalance.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        maxBalance.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: editorValue.count))
        maxBalance.typeText("5000")
        app.buttons["Bitti"].firstMatch.tap()
        XCTAssertNotEqual(maxBalance.value as? String, editorValue)

        // Düzenle'deki tutar değişmedi.
        app.tabBars.buttons["Düzenle"].tap()
        XCTAssertTrue(editorBalance.waitForExistence(timeout: 5))
        XCTAssertEqual(editorBalance.value as? String, editorValue)
    }

    /// Gün girilip Maksimize Et'e basılınca detay açılır; geri dönünce geçmişte bir
    /// satır vardır. Değerler assert EDİLMEZ (sayılar birim testlerinde).
    @MainActor
    func testMaxPlanOpensDetailAndAddsHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: geçmiş boş başlar
        app.launch()

        // Düzenle'de tutar + oran + EFT ücreti.
        app.tabBars.buttons["Düzenle"].tap()
        let balance = app.textFields["balanceField"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        balance.tap()
        balance.typeText("100000")
        app.buttons["Bitti"].firstMatch.tap()
        let rate = app.textFields["rateField"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()
        rate.typeText("45")
        app.buttons["Bitti"].firstMatch.tap()
        let eftFee = app.textFields["eftFeeField"]
        tapWhenSettled(eftFee)
        eftFee.typeText("5")
        app.buttons["Bitti"].firstMatch.tap()

        // Max: geçmiş boş; gün girilmeden buton kapalı.
        app.tabBars.buttons["Max"].tap()
        XCTAssertTrue(element(app, "maxHistoryEmpty").waitForExistence(timeout: 5))
        let maximize = app.buttons["maxMaximizeButton"]
        XCTAssertTrue(maximize.exists)
        XCTAssertFalse(maximize.isEnabled)

        let days = app.textFields["maxDaysField"]
        days.tap()
        days.typeText("10")
        app.buttons["Bitti"].firstMatch.tap()
        XCTAssertTrue(maximize.isEnabled)
        maximize.tap()

        // Detay açıldı.
        XCTAssertTrue(element(app, "maxDetailRoot").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "maxDetailTotalNet").exists)
        XCTAssertTrue(element(app, "maxAllocation_0").exists)

        // Geri: geçmişte tarihli satır var, boş durum yok.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(app, "maxHistoryRow_0").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "maxHistoryEmpty").exists)

        // Geçmiş satırı aynı detayı açar.
        element(app, "maxHistoryRow_0").tap()
        XCTAssertTrue(element(app, "maxDetailRoot").waitForExistence(timeout: 5))
    }

    /// Temizle önce onay ister: Vazgeç geçmişi korur, onay hepsini siler.
    @MainActor
    func testMaxHistoryClearAsksBeforeDeleting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]   // kalıcılığı atla: geçmiş boş başlar
        app.launch()

        // Boş geçmişte Temizle görünmez.
        app.tabBars.buttons["Max"].tap()
        XCTAssertTrue(element(app, "maxHistoryEmpty").waitForExistence(timeout: 5))
        let clear = app.buttons["maxHistoryClearButton"]
        XCTAssertFalse(clear.exists)

        makeMaxPlan(app)
        XCTAssertTrue(element(app, "maxHistoryRow_0").waitForExistence(timeout: 5))
        XCTAssertTrue(clear.exists)

        // Vazgeç: geçmiş korunur.
        clear.tap()
        let cancel = app.buttons["Vazgeç"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(element(app, "maxHistoryRow_0").exists)

        // Onay: geçmiş boşalır, Temizle kaybolur.
        clear.tap()
        let confirm = app.buttons["Geçmişi Temizle"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element(app, "maxHistoryEmpty").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "maxHistoryRow_0").exists)
        XCTAssertFalse(clear.exists)
    }

    /// Düzenle'de tutar + oran girer, Max'ta 10 günlük plan hesaplar, detaydan geri döner.
    @MainActor
    private func makeMaxPlan(_ app: XCUIApplication) {
        app.tabBars.buttons["Düzenle"].tap()
        let balance = app.textFields["balanceField"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        balance.tap()
        balance.typeText("100000")
        app.buttons["Bitti"].firstMatch.tap()
        let rate = app.textFields["rateField"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()
        rate.typeText("45")
        app.buttons["Bitti"].firstMatch.tap()

        app.tabBars.buttons["Max"].tap()
        let days = app.textFields["maxDaysField"]
        XCTAssertTrue(days.waitForExistence(timeout: 5))
        days.tap()
        days.typeText("10")
        app.buttons["Bitti"].firstMatch.tap()
        app.buttons["maxMaximizeButton"].tap()
        XCTAssertTrue(element(app, "maxDetailRoot").waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
