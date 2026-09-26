//
//  MaxScreen.swift
//  InterestCalculator
//
//  Tab 4 — Max. Tutarı kayıtlı bankalara, girilen gün sayısının sonunda en
//  yüksek toplam net kazancı verecek şekilde böler (MaxPlanner). "Maksimize Et"
//  sonucu detay sayfasında açar ve geçmişin başına ekler; geçmiş satırları hesap
//  tarihini gösterir ve aynı detayı açar.
//
//  • Tutar bu ekranın KENDİ @State'idir (Karşılaştır ile aynı model): ilk
//    görünüşte Düzenle'deki tutarla BİR KEZ tohumlanır, sonra bağımsızdır —
//    burada değiştirmek Düzenle'yi etkilemez. Gün sayısı da yereldir; ikisi de
//    kalıcı değildir. Bankalar ve stopaj Düzenle'den gelir.
//  • Plan bugünden başlar, hafta sonu snap'i yok (Karşılaştır gibi).
//  • Geçmiş kalıcıdır (AppState.maxHistory), en yeni üstte.
//  • Düzen: tutar, gün ve buton sabit; geçmiş altında kendi ScrollView'unda
//    kayar. Büyük erişilebilirlik boyutunda ve yatayda (alçak ekran) her şey tek
//    ScrollView'dadır — sabit kısım ekranı doldurup listeyi yutmasın.
//  Zemin düz snowfield — gece gradyanı yalnız Özet'in.
//

import SwiftUI

struct MaxScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.displayScale) private var displayScale
    @FocusState private var focused: EditorField?
    /// Max'ın kendi tutarı (ham metin). nil = henüz tohumlanmadı; o ana kadar
    /// Düzenle'deki tutar okunur ama hiçbir zaman YAZILMAZ.
    @State private var balanceText: String?
    @State private var daysText = ""
    @State private var isComputing = false
    /// Açık detay sayfaları (plan kayıtlarının id'leri).
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            layout
                .background(Color.snowfield.ignoresSafeArea())
                // Çubuk kökte gizli; başlık yalnız detaydaki geri düğmesinde görünür.
                .navigationTitle("Max")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { id in
                    if let record = state.maxHistory.first(where: { $0.id == id }) {
                        MaxPlanDetailScreen(record: record)
                    }
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
        .onAppear {
            // Tutar Düzenle'den YALNIZ bir kez alınır. Düzenle'deki tutar boşken
            // tohumlanmaz: önce buraya bakıp sonra Düzenle'de tutar giren
            // kullanıcı boş tutara kilitlenmesin.
            if balanceText == nil, !state.balanceText.isEmpty {
                balanceText = state.balanceText
            }
        }
    }

    // MARK: - Düzen

    @ViewBuilder
    private var layout: some View {
        if dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    planSection
                    historyHeader
                    historyList
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // `.contain`: kök kimliği çocuklara yayılıp iç kimlikleri ezmesin.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("maxRoot")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Sabit kısım önce ideal yüksekliğini alır, kalan alan listenin;
                // yoksa ScrollView açıklama satırlarını kesilmeye zorlar.
                planSection
                    .padding([.horizontal, .top], 16)
                    .layoutPriority(1)
                historyHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .layoutPriority(1)
                ScrollView {
                    historyList
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("maxRoot")
        }
    }

    // MARK: - Tutar, gün, buton

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputsCard
            maximizeButton
            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.slate)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                DecimalTextField(unit: "₺", text: balanceBinding, field: .balance, focused: $focused,
                                 kind: .money, identifier: "maxBalanceField")
            } label: {
                Text("Toplam tutar").foregroundStyle(.ink)
            }
            Text("Düzenle'deki tutarla başlar; buradaki değişiklik Düzenle'yi etkilemez.")
                .font(.caption)
                .foregroundStyle(.slate)

            Rectangle().fill(Color.rime).frame(height: 1 / displayScale)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Kaç günlük plan yapmak istersiniz?")
                    .foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                TextField("0", text: $daysText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                    .frame(width: 56)
                    .focused($focused, equals: .planDays)
                    .accessibilityLabel("Plan süresi, gün")
                    .accessibilityIdentifier("maxDaysField")
                Text("gün").foregroundStyle(.slate)
            }
        }
        .tint(.glacier)
        .padding(16)
        .cardSurface()
    }

    private var maximizeButton: some View {
        let isReady = validationMessage == nil
        return Button(action: maximize) {
            HStack(spacing: 10) {
                if isComputing {
                    ProgressView().tint(.onAccent)
                    Text("Hesaplanıyor…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Maksimize Et")
                }
            }
            .font(.title3.weight(.bold))
            // Pasif dolgu gri: onAccent (koyu modda ink) orada okunmaz.
            .foregroundStyle(isReady ? Color.onAccent : Color.slate)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .controlSize(.large)
        .tint(.glacier)
        // Hesap sürerken buton rengini korur (içinde spinner); ikinci dokunuşu
        // `maximize()` yok sayar.
        .disabled(!isReady)
        .accessibilityHint("Tutarı bankalara en yüksek net kazanç için böler ve sonucu açar")
        .accessibilityIdentifier("maxMaximizeButton")
    }

    // MARK: - Geçmiş

    private var historyHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Geçmiş")
                .font(.headline)
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !state.maxHistory.isEmpty {
                Text("\(state.maxHistory.count) hesap")
                    .font(.caption)
                    .foregroundStyle(.slate)
            }
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if state.maxHistory.isEmpty {
            Text("Henüz hesap yok. Maksimize Et sonuçları burada, hesaplandıkları tarihle listelenir.")
                .font(.footnote)
                .foregroundStyle(.slate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("maxHistoryEmpty")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(state.maxHistory.enumerated()), id: \.element.id) { index, record in
                    NavigationLink(value: record.id) {
                        historyRow(record)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(historyAccessibility(record))
                    .accessibilityIdentifier("maxHistoryRow_\(index)")
                }
            }
        }
    }

    private func historyRow(_ record: MaxPlanRecord) -> some View {
        let plan = record.plan
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(moneyText(plan.amount)) · \(plan.nights) gün")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                    .monospacedDigit()
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.slate)
                if !plan.allocations.isEmpty {
                    Text(plan.allocations.map(\.bankName).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.slate)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(moneyText(plan.totalNet))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(plan.totalNet > 0 ? Color.aurora : Color.slate)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("net kazanç")
                    .font(.caption2)
                    .foregroundStyle(.slate)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.slate)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(.rect)
    }

    private func historyAccessibility(_ record: MaxPlanRecord) -> String {
        let plan = record.plan
        let date = record.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(date): \(moneyText(plan.amount)), \(plan.nights) gün, net kazanç \(moneyText(plan.totalNet))"
    }

    // MARK: - Hesap

    /// Tutar alanının bağlaması. Yalnız yerel `balanceText`'e yazar — Düzenle'ye YAZMAZ.
    private var balanceBinding: Binding<String> {
        Binding(
            get: { balanceText ?? state.balanceText },
            set: { balanceText = $0 }
        )
    }

    private var parsedAmount: Money? {
        guard let value = DecimalInputParser.parse(balanceText ?? state.balanceText), value > 0 else {
            return nil
        }
        return value
    }

    private var parsedDays: Int? {
        guard let days = Int(daysText.trimmingCharacters(in: .whitespacesAndNewlines)),
              MaxPlanner.dayRange.contains(days) else { return nil }
        return days
    }

    /// Buton neden kapalı; hazırsa nil.
    private var validationMessage: String? {
        if parsedAmount == nil {
            return "Planlamak için tutar girin."
        }
        if daysText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Kaç günlük plan istediğinizi girin."
        }
        if parsedDays == nil {
            return "Gün sayısı \(MaxPlanner.dayRange.lowerBound) ile \(MaxPlanner.dayRange.upperBound) arasında olmalı."
        }
        if !state.banks.contains(where: { (DecimalInputParser.parse($0.annualRateText) ?? 0) > 0 }) {
            return "Düzenle'de oranı girilmiş en az bir banka gerekli."
        }
        return nil
    }

    private func maximize() {
        guard let amount = parsedAmount, let days = parsedDays, !isComputing else { return }
        focused = nil
        isComputing = true
        let banks = state.planningConditions
        let withholding = state.withholdingRule
        let start = AccrualCalendar.today()
        let weekday = AccrualCalendar.weekday(for: start)
        Task {
            // Uzun vadede binlerce motor çağrısı: ana iş parçacığını bloklamasın.
            let plan = await Task.detached(priority: .userInitiated) {
                MaxPlanner.plan(amount: amount, banks: banks, withholding: withholding,
                                nights: days, startWeekday: weekday)
            }.value
            let record = MaxPlanRecord(id: UUID(), createdAt: Date(), startDate: start, plan: plan)
            state.recordMaxPlan(record)
            isComputing = false
            path.append(record.id)
        }
    }

    private func moneyText(_ value: Money) -> String {
        value.formatted(.currency(code: "TRY"))
    }
}

#Preview {
    MaxScreen()
        .environment(AppState.preview)
}
