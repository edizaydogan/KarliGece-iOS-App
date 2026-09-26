//
//  CompareScreen.swift
//  InterestCalculator
//
//  Tab 3 — Karşılaştır. Kayıtlı bankalardan 2 ya da 3'ü AYNI tutar için yan
//  yana: ekran eşit sütunlara bölünür, her sütun bir banka; yukarıdan aşağıya
//  brüt/net yıllık oran, 1/7/30/90/365 günlük net kazanç ve bakiye dağılımı.
//
//  • Seçim bu ekranın KENDİ @State'idir: 1. sütun ilk görünüşte Özet'in seçili
//    bankasıyla BİR KEZ tohumlanır, sonra iki yönde de Özet'ten bağımsızdır.
//    Kalıcı değildir (her açılışta yeniden tohumlanır).
//  • Vade Özet'ten GELMEZ: sabit vadeler bugünden başlar, hafta sonu snap'i yok.
//  • Tutar da bu ekranın KENDİ @State'idir: alan ilk göründüğünde Düzenle'deki
//    "Toplam tutar"la (`state.balanceText`) BİR KEZ tohumlanır, sonra iki yönde
//    de bağımsızdır — burada değiştirmek Düzenle'yi (dolayısıyla Özet'i)
//    etkilemez. Kalıcı değildir.
//  • Tablo body başında BİR KEZ hesaplanır; hücreler hesap yapmaz.
//  Zemin düz snowfield — gece gradyanı yalnız Özet'in.
//

import SwiftUI

struct CompareScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @FocusState private var focused: EditorField?
    /// Karşılaştır'ın kendi banka seçimi. nil = henüz tohumlanmadı.
    @State private var selection: CompareSelection?
    /// Karşılaştır'ın kendi tutarı (ham metin). nil = henüz tohumlanmadı; o ana
    /// kadar Düzenle'deki tutar okunur ama hiçbir zaman YAZILMAZ.
    @State private var balanceText: String?

    private let valorNote = "Kazançlar bugünden başlar. Hafta içi kazanç ertesi gün, hafta sonu (Cuma–Pazar) kazancı Pazartesi valörüyle bakiyeye eklenip bileşiklenir."

    var body: some View {
        let current = selection ?? CompareSelection(seed: state.selectedBank?.id)
        let balance = balanceBinding
        let table = CompareTable(state: state, selection: current,
                                 balance: DecimalInputParser.parse(balance.wrappedValue))

        ZStack {
            Color.snowfield.ignoresSafeArea()
            if table.columns.isEmpty {
                emptyState
            } else {
                content(table, current: current, balance: balance)
                    .onAppear {
                        // Tutar, alan İLK göründüğünde Düzenle'den bir kez alınır.
                        // Boş durumda (tek banka) ya da Düzenle'deki tutar boşken
                        // tohumlanmaz: önce buraya bakıp sonra Düzenle'de tutar
                        // giren kullanıcı boş tutara kilitlenmesin.
                        if balanceText == nil, !state.balanceText.isEmpty {
                            balanceText = state.balanceText
                        }
                    }
            }
        }
        .onAppear {
            // Özet'in seçimi YALNIZ ilk görünüşte, bir kez çekilir. TabView
            // @State'i sekme değişimlerinde korur; sonraki görünüşler tohumlamaz.
            if selection == nil {
                selection = CompareSelection(seed: state.selectedBank?.id)
            }
        }
        // `.contain`: kök kimliği çocuklara yayılıp iç kimlikleri ezmesin.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compareRoot")
    }

    // MARK: - İçerik

    private func content(_ table: CompareTable, current: CompareSelection,
                         balance: Binding<String>) -> some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                balanceCard(balance)
                if state.banks.count >= 3 {
                    columnCountPicker(current)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    // Büyük erişilebilirlik boyutunda sütunlar sığmaz: her banka
                    // kendi kartında, alt alta.
                    ForEach(0..<table.columns.count, id: \.self) { column in
                        stackedCard(table, column: column, current: current)
                    }
                } else {
                    Section {
                        ratesCard(table)
                        earningsCard(table)
                        distributionCard(table)
                    } header: {
                        headerRow(table, current: current)
                    }
                }
                notesSection(table)
                disclaimer
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // Durum çubuğu bölgesi opak: sabit başlığın üstünde kayan içerik görünmesin.
        .overlay(alignment: .top) {
            Color.snowfield
                .ignoresSafeArea(edges: .top)
                .frame(height: 0)
                .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                // TabView diğer sekmeleri de canlı tutar; korumasız buton üst üste biner.
                if focused != nil {
                    Spacer()
                    Button("Bitti") { focused = nil }
                }
            }
        }
    }

    // MARK: - Tutar + sütun sayısı

    /// Tutar alanının bağlaması. Yalnız yerel `balanceText`'e yazar — Düzenle'ye YAZMAZ.
    private var balanceBinding: Binding<String> {
        Binding(
            get: { balanceText ?? state.balanceText },
            set: { balanceText = $0 }
        )
    }

    private func balanceCard(_ balance: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                DecimalTextField(unit: "₺", text: balance, field: .balance, focused: $focused,
                                 kind: .money, identifier: "compareBalanceField")
            } label: {
                Text("Toplam tutar").foregroundStyle(.ink)
            }
            Text("Düzenle'deki tutarla başlar; buradaki değişiklik Düzenle'yi etkilemez.")
                .font(.caption)
                .foregroundStyle(.slate)
        }
        .tint(.glacier)
        .padding(16)
        .cardSurface()
    }

    private func columnCountPicker(_ current: CompareSelection) -> some View {
        let count = Binding<Int>(
            get: { current.columnCount },
            set: { newCount in
                var updated = current
                updated.setColumnCount(newCount)
                selection = updated
            }
        )
        return Picker("Karşılaştırılacak banka sayısı", selection: count) {
            Text("2 banka").tag(2)
            Text("3 banka").tag(3)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("compareColumnCountPicker")
    }

    // MARK: - Sütun başlıkları (dropdown)

    /// Kaydırırken tepede sabit kalır (opak zemin), yoksa sütun ↔ banka eşlemesi kaybolur.
    private func headerRow(_ table: CompareTable, current: CompareSelection) -> some View {
        CompareColumnsRow(count: table.columns.count) { column in
            bankHeader(table, column: column, current: current)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.snowfield)
        .overlay(alignment: .bottom) { hairline }
    }

    private func bankHeader(_ table: CompareTable, column: Int, current: CompareSelection) -> some View {
        let bank = table.columns[column]
        let notes = table.notes[column]
        return VStack(spacing: 4) {
            bankMenu(bank, name: table.names[column], column: column, current: current)
            HStack(spacing: 3) {
                Text(rateCaption(bank))
                if !notes.isEmpty {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(notes.contains { $0.tone == .error } ? Color.ember : Color.slate)
                        .accessibilityLabel("Not var, ayrıntısı aşağıda")
                }
            }
            .font(.caption2)
            .foregroundStyle(.slate)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // Rozet konuma bağlı değil: o an Özet'te seçili bankanın sütununda.
            if bank.id == state.selectedBank?.id {
                Label("Özet", systemImage: "moon.stars")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.glacier)
                    .accessibilityLabel("Özet'te seçili banka")
            }
        }
    }

    /// Sütunun banka menüsü. Yalnız yerel `selection`'ı değiştirir — Özet'e YAZMAZ.
    /// Başka sütundaki banka seçilirse iki sütun yer değiştirir.
    private func bankMenu(_ bank: BankConditionDraft, name: String, column: Int,
                          current: CompareSelection) -> some View {
        let bankIDs = state.banks.map(\.id)
        let binding = Binding<UUID>(
            get: { bank.id },
            set: { id in
                var updated = current
                updated.select(id, forColumn: column, in: bankIDs)
                selection = updated
            }
        )
        return Menu {
            Picker("Banka", selection: binding) {
                ForEach(state.banks) { option in
                    Text(state.displayName(for: option)).tag(option.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.glacier)
            }
        }
        .accessibilityLabel("\(column + 1). sütun bankası: \(name)")
        .accessibilityHint("Bu sütunda karşılaştırılacak bankayı değiştirir")
        .accessibilityIdentifier("compareBankMenu_\(column)")
    }

    /// İlan edilen oran ve tabanı ("%45 · brüt").
    private func rateCaption(_ bank: BankConditionDraft) -> String {
        guard let rate = DecimalInputParser.parse(bank.annualRateText) else { return "Oran yok" }
        let basis = bank.rateBasis == .net ? "net" : "brüt"
        return "%\(rate.grouped(fractionDigits: 0...2)) · \(basis)"
    }

    // MARK: - Kartlar

    private func ratesCard(_ table: CompareTable) -> some View {
        card("Oranlar") {
            metricRow("Brüt faiz (yıllık)", count: table.columns.count) { column in
                valueCell(percentText(table.oneDay(column)?.grossEffectiveAnnualRate),
                          accessibility: "\(table.names[column]), brüt faiz yıllık")
            }
            metricRow("Net faiz (yıllık)", count: table.columns.count) { column in
                valueCell(percentText(table.oneDay(column)?.netEffectiveAnnualRate),
                          accessibility: "\(table.names[column]), net faiz yıllık")
            }
        }
    }

    private func earningsCard(_ table: CompareTable) -> some View {
        card("Net kazanç", caption: "Bugünden başlayarak, valör kurallı bileşik") {
            ForEach(Array(CompareCalculator.horizons.enumerated()), id: \.offset) { horizon, days in
                metricRow("\(days) günlük", count: table.columns.count) { column in
                    earningsCell(table, horizon: horizon, column: column)
                }
            }
        }
    }

    private func distributionCard(_ table: CompareTable) -> some View {
        let count = table.columns.count
        let showsExcess = (0..<count).contains { (table.oneDay($0)?.excessAboveCap ?? 0) > 0 }
        return card("Bakiye dağılımı (başlangıç)") {
            metricRow("Vadesiz kalan", count: count) { column in
                valueCell(moneyText(table.oneDay(column)?.idleAmount),
                          accessibility: "\(table.names[column]), vadesiz kalan")
            }
            metricRow("Faize giren", count: count) { column in
                valueCell(moneyText(table.oneDay(column)?.interestBearingBalance),
                          accessibility: "\(table.names[column]), faize giren")
            }
            if showsExcess {
                metricRow("Limit üstü (faizsiz)", count: count) { column in
                    valueCell(moneyText(table.oneDay(column)?.excessAboveCap),
                              accessibility: "\(table.names[column]), limit üstü faizsiz")
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, caption: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.slate)
                }
            }
            content()
        }
        // Yatay iç boşluk başlık satırıyla AYNI (12) — sütunlar hizalı kalsın.
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Satırlar ve hücreler

    /// Tam genişlik satır başlığı + altında eşit sütunlu değerler.
    private func metricRow<Cell: View>(_ label: String, count: Int,
                                       @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.slate)
                .accessibilityAddTraits(.isHeader)
            CompareColumnsRow(count: count, cell: cell)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// VoiceOver satır satır okur: etiket banka adını içermeli.
    private func valueCell(_ text: String, accessibility: String) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel("\(accessibility), \(text == "—" ? "değer yok" : text)")
    }

    /// Net kazanç hücresi: kazanan aurora + ikon, diğerleri altında "−₺X" farkı
    /// (renk tek başına anlam taşımaz).
    @ViewBuilder
    private func earningsCell(_ table: CompareTable, horizon: Int, column: Int) -> some View {
        let days = CompareCalculator.horizons[horizon]
        let label = "\(table.names[column]), \(days) günlük net kazanç"
        if let net = table.net(column, horizon) {
            let rank = table.ranks[horizon][column]
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text(moneyText(net))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(rank.isBest ? Color.aurora : Color.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if rank.isBest {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.aurora)
                    }
                }
                if let shortfall = rank.shortfall {
                    Text("−" + moneyText(shortfall))
                        .font(.caption)
                        .foregroundStyle(.slate)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(earningsAccessibility(label, net: net, rank: rank))
            .accessibilityIdentifier("compareNet_\(days)_\(column)")
        } else {
            valueCell("—", accessibility: label)
        }
    }

    private func earningsAccessibility(_ label: String, net: Money, rank: CompareRank) -> String {
        var text = "\(label), \(moneyText(net))"
        if rank.isBest { text += ", en yüksek" }
        if let shortfall = rank.shortfall { text += ", en yüksekten \(moneyText(shortfall)) az" }
        return text
    }

    // MARK: - Büyük erişilebilirlik boyutu: yığılmış düzen

    private func stackedCard(_ table: CompareTable, column: Int, current: CompareSelection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            bankHeader(table, column: column, current: current)
                .frame(maxWidth: .infinity)
            stackedRow("Brüt faiz (yıllık)", percentText(table.oneDay(column)?.grossEffectiveAnnualRate))
            stackedRow("Net faiz (yıllık)", percentText(table.oneDay(column)?.netEffectiveAnnualRate))
            ForEach(Array(CompareCalculator.horizons.enumerated()), id: \.offset) { horizon, _ in
                stackedEarningsRow(table, horizon: horizon, column: column)
            }
            stackedRow("Vadesiz kalan", moneyText(table.oneDay(column)?.idleAmount))
            stackedRow("Faize giren", moneyText(table.oneDay(column)?.interestBearingBalance))
            if let excess = table.oneDay(column)?.excessAboveCap, excess > 0 {
                stackedRow("Limit üstü (faizsiz)", moneyText(excess))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func stackedEarningsRow(_ table: CompareTable, horizon: Int, column: Int) -> some View {
        let days = CompareCalculator.horizons[horizon]
        let label = "\(days) günlük net kazanç"
        if let net = table.net(column, horizon) {
            let rank = table.ranks[horizon][column]
            stackedRow(label, stackedEarningsText(net: net, rank: rank), emphasized: rank.isBest)
                .accessibilityIdentifier("compareNet_\(days)_\(column)")
        } else {
            stackedRow(label, "—")
        }
    }

    private func stackedEarningsText(net: Money, rank: CompareRank) -> String {
        var text = moneyText(net)
        if rank.isBest { text += " · en yüksek" }
        if let shortfall = rank.shortfall { text += " · −\(moneyText(shortfall))" }
        return text
    }

    private func stackedRow(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.slate)
            Text(value)
                .font(.system(.body, design: .rounded).weight(emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? Color.aurora : Color.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Notlar, açıklamalar + disclaimer

    /// Uzun cümleler dar sütunlara sığmaz: tablo yalnız işaret taşır, tam metin
    /// burada. Oran ve valör açıklamaları da tabloyu kısaltmak için en altta.
    private func notesSection(_ table: CompareTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if table.hasNotes {
                Text("Notlar")
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(table.sharedNotes.enumerated()), id: \.offset) { _, note in
                    noteText(note.text, tone: note.tone)
                }
                ForEach(0..<table.columns.count, id: \.self) { column in
                    ForEach(Array(table.notes[column].enumerated()), id: \.offset) { _, note in
                        noteText("\(table.names[column]): \(note.text)", tone: note.tone)
                    }
                }
                Spacer().frame(height: 4)
            }
            noteText("Oranlar: vadesiz şart, limit ve \(withholdingLabel) stopaj dahil, bileşiksiz yıllık oran (365 gün). Bileşiğin etkisi kazanç satırlarında görünür.", tone: .info)
            noteText(valorNote, tone: .info)
            noteText("Buradaki tutar ve banka seçimleri Düzenle'yi ve Özet'i etkilemez.", tone: .info)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func noteText(_ text: String, tone: ResultMessages.Tone) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tone == .error ? Color.ember : Color.slate)
    }

    private var disclaimer: some View {
        Text(ResultMessages.disclaimer)
            .font(.footnote)
            .foregroundStyle(.slate)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Boş durum

    private var emptyState: some View {
        ContentUnavailableView {
            // Kimlik başlıkta: görünüm kökün tek çocuğu olduğundan kapsayıcıya
            // verilen kimlik `compareRoot` ile birleşip kayboluyor.
            Label("Karşılaştırmak için en az iki banka gerekli", systemImage: "chart.line.uptrend.xyaxis")
                .accessibilityIdentifier("compareEmptyState")
        } description: {
            Text("Düzenle sekmesinden bir banka daha ekleyin.")
        } actions: {
            Button {
                state.selectedTab = .editor
            } label: {
                Text("Düzenle'ye git").fontWeight(.semibold).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.glacier)
        }
    }

    // MARK: - Biçim yardımcıları

    /// Özet'teki `withholdingLabel` ile aynı mantık; oran koda gömülmez.
    private var withholdingLabel: String {
        if let value = DecimalInputParser.parse(state.withholdingText) {
            return "%\(value.grouped(fractionDigits: 0...2))"
        }
        return "%0"
    }

    private func percentText(_ value: Percentage?) -> String {
        value.map { "%\($0.percentValue.grouped(fractionDigits: 2))" } ?? "—"
    }

    private func moneyText(_ value: Money?) -> String {
        value.map { $0.formatted(.currency(code: "TRY")) } ?? "—"
    }

    private var hairline: some View {
        Rectangle().fill(Color.rime).frame(height: 1 / displayScale)
    }
}

// MARK: - Tablo verisi

/// Tek render'da BİR KEZ hesaplanan tablo verisi; alt görünümler yalnız okur.
/// Maliyet: sütun başına 1+7+30+90+365 = 493 gece (3 sütunda ~1.500 tek-gece
/// motor çağrısı). Cache/debounce bilinçli olarak YOK.
private struct CompareTable {
    let columns: [BankConditionDraft]
    let names: [String]
    /// [sütun][vade]; tutar ayrıştırılamıyorsa nil (hücreler "—").
    let results: [[InterestResult]]?
    /// [vade][sütun] — her vade satırı ayrı sıralanır.
    let ranks: [[CompareRank]]
    /// Sütun başına tam cümle notlar (1 günlük sonucun tanılamalarından).
    let notes: [[ResultMessages.Warning]]
    /// Tüm bankalara ortak uyarılar (stopaj) — bir kez gösterilir.
    let sharedNotes: [ResultMessages.Warning]

    /// `balance`: Karşılaştır'ın KENDİ tutarı (Düzenle'deki değil); nil → hücreler "—".
    init(state: AppState, selection: CompareSelection, balance: Money?) {
        let ids = selection.resolvedIDs(in: state.banks.map(\.id))
        let columns = ids.compactMap { id in state.banks.first { $0.id == id } }
        self.columns = columns
        names = columns.map { state.displayName(for: $0) }

        guard let balance, !columns.isEmpty else {
            results = nil
            ranks = []
            notes = columns.map { _ in [] }
            sharedNotes = []
            return
        }
        let projected = CompareCalculator.projections(
            balance: balance,
            conditions: columns.map { $0.makeCondition() },
            withholding: state.withholdingRule,
            startWeekday: AccrualCalendar.weekday(for: AccrualCalendar.today())
        )
        results = projected
        ranks = CompareCalculator.horizons.indices.map { horizon in
            CompareCalculator.rank(projected.map { $0[horizon].netInterest })
        }
        notes = projected.map { Self.columnNotes(for: $0[0]) }
        sharedNotes = projected.contains { $0[0].diagnostics.contains(.deductionRatesExceedTotal) }
            ? ResultMessages.warnings(for: [.deductionRatesExceedTotal])
            : []
    }

    var hasNotes: Bool {
        !sharedNotes.isEmpty || notes.contains { !$0.isEmpty }
    }

    /// 1 günlük sonuç — oranlar, bakiye dağılımı ve notlar bundan.
    func oneDay(_ column: Int) -> InterestResult? {
        results?[column][0]
    }

    func net(_ column: Int, _ horizon: Int) -> Money? {
        results?[column][horizon].netInterest
    }

    /// Bir bankanın notları. Stopaj uyarısı ortaktır, burada tekrarlanmaz.
    private static func columnNotes(for oneDay: InterestResult) -> [ResultMessages.Warning] {
        var notes: [ResultMessages.Warning] = []
        if let reason = ResultMessages.zeroEarningsReason(for: oneDay, nights: 1) {
            // Uzun vadeler kuruşu aşabilir: yalnız 1 günlüğün kuruş altı olduğu söylenir.
            let text = reason == .belowOneKurus ? "1 günlük kazanç kuruşun altında kalıyor" : reason.text
            notes.append(.init(text: text, tone: .info))
        }
        if oneDay.diagnostics.contains(.zeroRate) {
            notes.append(.init(text: "Oran girilmemiş", tone: .info))
        }
        notes += ResultMessages.warnings(for: oneDay.diagnostics.filter { $0 != .deductionRatesExceedTotal })
        return notes
    }
}

#Preview {
    CompareScreen()
        .environment(AppState.preview)
}
