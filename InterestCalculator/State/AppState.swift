//
//  AppState.swift
//  InterestCalculator
//
//  Tek sahiplik noktası. Ham String girdileri + motor çağrısı. Debounce/cache YOK.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    /// HAM metin — kaynağın doğrusu. Biçimlendirme Presentation'da.
    var balanceText: String = ""
    /// Stopaj yüzdesi, ön dolu "15" (kullanıcı düzenler; oran koda gömülmez).
    var withholdingText: String = "15"
    var nights: Int = 1
    var banks: [BankConditionDraft] = [.blankDefault]
    var selectedBankID: UUID?

    init() {}

    /// Seçili banka; seçim geçersizse listenin ilkine düşer.
    var selectedBank: BankConditionDraft? {
        if let id = selectedBankID, let match = banks.first(where: { $0.id == id }) {
            return match
        }
        return banks.first
    }

    /// Canlı hesap sonucu. Bakiye ayrıştırılamıyorsa veya banka yoksa nil.
    var result: InterestResult? {
        guard let balance = DecimalInputParser.parse(balanceText),
              let draft = selectedBank else {
            return nil
        }
        let withholding: WithholdingRule = DecimalInputParser.parse(withholdingText)
            .map { .single(.percent($0)) } ?? .none
        return InterestEngine.calculate(
            InterestInput(
                totalBalance: balance,
                nights: nights,
                condition: draft.makeCondition(),
                withholding: withholding
            )
        )
    }

    /// Sonucu bloklayan (.error) tanılamalar.
    var blockingIssues: [CalculationDiagnostic] {
        result?.blockingIssues ?? []
    }

    /// Önizleme fixture'ı — her #Preview bununla sarılır, yoksa @Environment crash eder.
    static var preview: AppState {
        let state = AppState()
        state.balanceText = "100.000"
        state.withholdingText = "15"
        state.nights = 1
        state.banks = [.sample]
        state.selectedBankID = state.banks.first?.id
        return state
    }
}
