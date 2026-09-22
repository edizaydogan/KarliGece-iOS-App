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
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testAllThreeTabsOpen() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Özet"].tap()
        XCTAssertTrue(element(app, "summaryRoot").waitForExistence(timeout: 5))

        app.tabBars.buttons["Düzenle"].tap()
        XCTAssertTrue(element(app, "editorRoot").waitForExistence(timeout: 5))

        app.tabBars.buttons["Karşılaştır"].tap()
        XCTAssertTrue(element(app, "compareRoot").waitForExistence(timeout: 5))
    }

    @MainActor
    func testEndToEndHappyPath() throws {
        let app = XCUIApplication()
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
}
