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
    @FocusState private var dayCountFocused: Bool

    private let cutoffNote = "Bankaların son işlem saati (cut-off) vardır; saat sınırından sonraki transferler ertesi iş günü valörüyle işleyebilir."
    private let valorNote = "Hafta içi kazanç ertesi gün 00:00, hafta sonu (Cuma–Pazar) Pazartesi 00:00 valörüyle bakiyeye eklenip bileşiklenir. Bitiş hafta sonuna denk gelirse ilk iş gününe (Pazartesi) alınır."

    var body: some View {
        @Bindable var state = state

        ScrollView {
            VStack(spacing: 16) {
                horizonSelector(state)

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

    // MARK: - Vade seçici (takvim + gün sayısı)

    private func horizonSelector(_ state: AppState) -> some View {
        let startBinding = Binding<Date>(
            get: { state.startDate },
            set: { state.setStartDate($0) }
        )
        let endBinding = Binding<Date>(
            get: { state.endDate },
            set: { state.setEndDate($0) }
        )
        let dayCountBinding = Binding<Int>(
            get: { state.nights },
            set: { state.setDayCount($0) }
        )
        let minEnd = AccrualCalendar.addNights(1, to: state.startDate)

        return VStack(alignment: .leading, spacing: 12) {
            DatePicker("Başlangıç", selection: startBinding, displayedComponents: .date)
                .accessibilityIdentifier("startDateField")
            DatePicker("Bitiş", selection: endBinding, in: minEnd..., displayedComponents: .date)
                .accessibilityIdentifier("endDateField")

            Rectangle().fill(Color.rime).frame(height: 1 / displayScale)

            HStack(spacing: 12) {
                Text("Gün sayısı").foregroundStyle(.ink)
                Spacer()
                TextField("1", value: dayCountBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                    .frame(width: 56)
                    .focused($dayCountFocused)
                    .accessibilityIdentifier("dayCountField")
                Text("gece").foregroundStyle(.slate)
                // Yön-farkında: "+" hafta sonunu ileri (Cuma→Pzt), "−" geri
                // (Pzt→Cuma) atlar. Değer bağlaması tek yönlü ileri snap'te
                // takıldığı için onIncrement/onDecrement kullanılır.
                Stepper("Gün sayısını değiştir",
                        onIncrement: { state.incrementDayCount() },
                        onDecrement: { state.decrementDayCount() })
                    .labelsHidden()
            }
            .font(.subheadline)

            Text(valorNote)
                .font(.caption)
                .foregroundStyle(.slate)
            Text(cutoffNote)
                .font(.caption)
                .foregroundStyle(.slate)
        }
        .tint(.glacier)
        .padding(16)
        .cardSurface()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if dayCountFocused {
                    Spacer()
                    Button("Bitti") { dayCountFocused = false }
                }
            }
        }
    }

    // MARK: - Hero

    /// Vade uzunluğuna göre başlık ("1 gecelik net kazanç" / "10 gecelik net kazanç").
    private var horizonLabel: String {
        "\(state.nights) gecelik net kazanç"
    }

    private func heroDisplay(_ result: InterestResult) -> (value: Money, color: Color, message: String?) {
        if result.netInterest > 0 {
            return (result.netInterest, .aurora, nil)
        }
        return (0, .slate, ResultMessages.zeroEarningsReason(for: result, nights: state.nights)?.text)
    }

    private func heroCard(_ result: InterestResult) -> some View {
        let display = heroDisplay(result)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let accessibility = "\(horizonLabel), \(display.value.formatted(.currency(code: "TRY")))"

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
            Text(horizonLabel)
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
        let messages = ResultMessages.warnings(for: result.diagnostics)
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, item in
                    Text(item.text)
                        .font(.footnote)
                        .foregroundStyle(item.tone == .error ? Color.ember : Color.slate)
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
            moneyRow("Net kazanç (\(state.nights) gece)", result.netInterest, emphasized: true)
            moneyRow("Vade sonu bakiyeniz", result.totalBalance + result.netInterest)
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
        return "Faize giren \(bearing) üzerinden \(rate) yıllık oranla \(nights) gece boyunca hesaplandı. Hafta içi kazanç ertesi gün 00:00 valörüyle bakiyeye eklenip bileşiklenir; Cuma–Pazar kazancı Pazartesi 00:00 valörüyle toplu işlenir. Toplam brüt \(gross), \(withholdingLabel) stopaj sonrası net \(net)."
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
        Text(ResultMessages.disclaimer)
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
