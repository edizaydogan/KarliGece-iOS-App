//
//  SummaryScreen.swift
//  InterestCalculator
//
//  Tab 1 — Özet. Gece göğü zemini, hero kart, üç aşamalı efektif oran satırı,
//  dağılım şelalesi, kademe rozeti, "Neden bu tutar?" ve disclaimer.
//  Renk tek başına anlam taşımaz: stopaj − işaretiyle, hata metinle desteklenir.
//

import SwiftUI

struct SummaryScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44

    private let disclaimerText = "Bu bir tahmindir; bankanızın fiilî tahakkuku kuruş farkı gösterebilir. Yatırım tavsiyesi değildir."
    private let cutoffNote = "Bankaların son işlem saati (cut-off) vardır; saat sınırından sonraki transferler ertesi iş günü valörüyle işleyebilir."

    var body: some View {
        @Bindable var state = state

        ScrollView {
            VStack(spacing: 16) {
                nightsSelector(state)

                if let result = state.result {
                    heroCard(result)
                    notes(result)
                    effectiveRateRow(result)
                    waterfallCard(result)
                    if let badge = appliedTierBadge(result) {
                        tierBadge(badge)
                    }
                    whyDisclosure(result)
                } else {
                    emptyState
                }

                disclaimer
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Rectangle().fill(.nightSky).ignoresSafeArea())
        .accessibilityIdentifier("summaryRoot")
    }

    // MARK: - Gece seçici

    private enum NightsMode: Hashable { case one, three, custom }

    private func nightsSelector(_ state: AppState) -> some View {
        let mode = Binding<NightsMode>(
            get: {
                if state.nights == 1 { return .one }
                if state.nights == 3 { return .three }
                return .custom
            },
            set: { newValue in
                switch newValue {
                case .one: state.nights = 1
                case .three: state.nights = 3
                case .custom: if state.nights == 1 || state.nights == 3 { state.nights = 7 }
                }
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Gece sayısı", selection: mode) {
                Text("1 gece").tag(NightsMode.one)
                Text("3 gece").tag(NightsMode.three)
                Text("Özel").tag(NightsMode.custom)
            }
            .pickerStyle(.segmented)

            if mode.wrappedValue == .custom {
                Stepper("\(state.nights) gece", value: Binding(get: { state.nights },
                                                               set: { state.nights = $0 }),
                        in: 0...365)
                .font(.subheadline)
                .foregroundStyle(.ink)
            }

            Text(cutoffNote)
                .font(.caption)
                .foregroundStyle(.slate)
        }
        .padding(16)
        .cardSurface()
    }

    // MARK: - Hero

    private func heroDisplay(_ result: InterestResult) -> (value: Money, color: Color, message: String?) {
        if result.netInterest > 0 {
            return (result.netInterest, .aurora, nil)
        }
        let diagnostics = result.diagnostics
        if diagnostics.contains(.belowMinimumBalance) {
            return (0, .slate, "Bu ürün daha yüksek bir bakiye gerektiriyor")
        }
        if diagnostics.contains(.requirementConsumesEntireBalance) {
            return (0, .slate, "Vadesiz şartı toplam bakiyenin tamamını kapsıyor")
        }
        if result.totalBalance > 0, state.nights > 0,
           result.totalGrossInterest == 0, !diagnostics.contains(.zeroRate) {
            return (0, .slate, "Bu tutarda gecelik kazanç kuruşun altında kalıyor")
        }
        return (0, .slate, nil)
    }

    private func heroCard(_ result: InterestResult) -> some View {
        let display = heroDisplay(result)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let accessibility = "Net gecelik kazanç, \(display.value.formatted(.currency(code: "TRY")))"

        return ZStack {
            shape.fill(Color.drift)

            Image(systemName: "snowflake")
                .font(.system(size: 140))
                .foregroundStyle(Color.ink.opacity(colorScheme == .dark ? 0.06 : 0.05))
                .rotationEffect(.degrees(12))
                .offset(x: 40, y: -30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)

            heroContent(display)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.rime, lineWidth: 1))
        .shadow(color: colorScheme == .dark ? .clear : Color.ink.opacity(0.06),
                radius: colorScheme == .dark ? 0 : 12, x: 0, y: colorScheme == .dark ? 0 : 4)
        .frame(maxWidth: 560)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility + (display.message.map { ". \($0)" } ?? ""))
        .accessibilityIdentifier("netResultValue")
    }

    @ViewBuilder
    private func heroContent(_ display: (value: Money, color: Color, message: String?)) -> some View {
        let number = Text(display.value, format: .currency(code: "TRY"))
            .font(dynamicTypeSize.isAccessibilitySize
                  ? .system(.largeTitle, design: .rounded).weight(.semibold)
                  : .system(size: heroSize, weight: .semibold, design: .rounded))
            .tracking(-0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .monospacedDigit()
            .foregroundStyle(display.color)

        VStack(spacing: 6) {
            number
            Text("Net gecelik kazanç")
                .font(.subheadline)
                .foregroundStyle(.slate)
            if let message = display.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.slate)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Uyarı notları

    @ViewBuilder
    private func notes(_ result: InterestResult) -> some View {
        let messages: [(String, Color)] = result.diagnostics.compactMap { diagnostic in
            switch diagnostic {
            case .idlePercentageAboveOneHundred: return ("Vadesiz yüzdesi %100'e sınırlandı.", .ember)
            case .deductionRatesExceedTotal: return ("Kesinti oranları toplamı %100'ü aşıyor.", .ember)
            case .unusuallyHighRate: return ("Girdiğiniz oran çok yüksek — günlük oran girmiş olabilir misiniz?", .slate)
            default: return nil
            }
        }
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, item in
                    Text(item.0).font(.footnote).foregroundStyle(item.1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Üç aşamalı efektif oran

    private var announcedRatePercent: Decimal? {
        guard let draft = state.selectedBank,
              let value = DecimalInputParser.parse(draft.annualRateText) else { return nil }
        return value
    }

    private func effectiveRateRow(_ result: InterestResult) -> some View {
        let announced = announcedRatePercent.map { "%\($0.grouped(fractionDigits: 0...2))" } ?? "—"
        let gross = result.grossEffectiveAnnualRate.map { "%\($0.percentValue.grouped(fractionDigits: 2))" } ?? "—"
        let net = result.netEffectiveAnnualRate.map { "%\($0.percentValue.grouped(fractionDigits: 2))" } ?? "—"

        return VStack(alignment: .leading, spacing: 12) {
            Text("İlan edilenden cebinize")
                .font(.headline)
                .foregroundStyle(.ink)
            HStack(spacing: 8) {
                stageChip("İlan edilen", announced, .slate)
                arrow
                stageChip("Paranıza brüt", gross, .glacier)
                arrow
                stageChip("Net", net, .aurora)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("İlan edilen \(announced), paranıza brüt \(gross), stopaj sonrası net \(net)")
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(.slate)
    }

    private func stageChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dağılım şelalesi

    private var withholdingLabel: String {
        if let value = DecimalInputParser.parse(state.withholdingText) {
            return "%\(value.grouped(fractionDigits: 0...2))"
        }
        return "%0"
    }

    private func waterfallCard(_ result: InterestResult) -> some View {
        VStack(spacing: 10) {
            moneyRow("Toplam paranız", result.totalBalance)
            moneyRow("Vadesiz kalan", result.idleAmount)
            moneyRow("Faize giren bakiye", result.interestBearingBalance)
            if result.excessAboveCap > 0 {
                moneyRow("Limit üstü (faizsiz)", result.excessAboveCap)
            }
            hairline
            moneyRow("Brüt faiz", result.totalGrossInterest)
            deductionRow("Stopaj (\(withholdingLabel))", result.totalDeductions)
            hairline
            moneyRow("Net gecelik kazanç", result.netInterest, emphasized: true)
        }
        .padding(16)
        .cardSurface()
    }

    private var hairline: some View {
        Rectangle().fill(Color.rime).frame(height: 1 / displayScale)
    }

    @ViewBuilder
    private func moneyRow(_ label: String, _ value: Money, emphasized: Bool = false) -> some View {
        let labelText = Text(label)
            .font(emphasized ? .headline : .body)
            .foregroundStyle(emphasized ? .ink : .slate)
        let valueText = Text(value, format: .currency(code: "TRY"))
            .font(emphasized ? .system(.headline, design: .rounded).weight(.semibold)
                             : .system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(.ink)
            .monospacedDigit()

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) { labelText; valueText }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack { labelText; Spacer(); valueText }
        }
    }

    @ViewBuilder
    private func deductionRow(_ label: String, _ value: Money) -> some View {
        let labelText = Text(label).font(.callout).foregroundStyle(.slate)
        let valueText = Text("− " + value.formatted(.currency(code: "TRY")))
            .font(.system(.callout, design: .rounded).weight(.medium))
            .foregroundStyle(.slate)
            .monospacedDigit()

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) { labelText; valueText }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack { labelText; Spacer(); valueText }
        }
    }

    // MARK: - Kademe rozeti

    private func appliedTierBadge(_ result: InterestResult) -> String? {
        guard let tier = result.breakdown.appliedTier else { return nil }
        let range: String
        switch (tier.lowerBound, tier.upperBound) {
        case (nil, let upper?):        range = "\(money0(upper)) ₺'nin altı"
        case (let lower?, let upper?): range = "\(money0(lower)) – \(money0(upper)) ₺ arası"
        case (let lower?, nil):        range = "\(money0(lower)) ₺ ve üzeri"
        case (nil, nil):               range = "Her tutar"
        }
        let requirement: String
        switch tier.requirement {
        case .fixedAmount(let amount): requirement = "\(money0(amount)) ₺ vadesiz"
        case .percentage(let pct):     requirement = "%\(pct.percentValue.grouped(fractionDigits: 0...2)) vadesiz"
        }
        return "\(range) → \(requirement)"
    }

    private func money0(_ value: Money) -> String { value.grouped(fractionDigits: 0) }

    private func tierBadge(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "stairs").foregroundStyle(.glacier)
            Text(text).font(.subheadline).foregroundStyle(.ink)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.frost)
        )
    }

    // MARK: - Neden bu tutar?

    private func whyDisclosure(_ result: InterestResult) -> some View {
        DisclosureGroup("Neden bu tutar?") {
            Text(explanation(result))
                .font(.footnote)
                .foregroundStyle(.slate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .tint(.glacier)
        .padding(16)
        .cardSurface()
    }

    private func explanation(_ result: InterestResult) -> String {
        let bearing = result.interestBearingBalance.formatted(.currency(code: "TRY"))
        let gross = result.totalGrossInterest.formatted(.currency(code: "TRY"))
        let net = result.netInterest.formatted(.currency(code: "TRY"))
        let rate = announcedRatePercent.map { "%\($0.grouped(fractionDigits: 0...2))" } ?? "girilen oran"
        let nights = state.nights
        return "Faize giren \(bearing) üzerinden \(rate) yıllık oranla \(nights) gecelik brüt faiz \(gross) hesaplandı; ardından \(withholdingLabel) stopaj düşülerek net \(net) bulundu."
    }

    // MARK: - Boş durum + disclaimer

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars")
                .font(.system(size: 44))
                .foregroundStyle(.glacier)
            Text("Başlamak için bakiyenizi ve bir banka kuralı girin")
                .font(.headline)
                .foregroundStyle(.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("resultPlaceholder")
            Button {
                state.selectedTab = .editor
            } label: {
                Text("Düzenle'ye git").fontWeight(.semibold).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.glacier)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardSurface(cornerRadius: 24)
        .frame(maxWidth: 560)
    }

    private var disclaimer: some View {
        Text(disclaimerText)
            .font(.footnote)
            .foregroundStyle(.slate)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

#Preview {
    SummaryScreen()
        .environment(AppState.preview)
}
