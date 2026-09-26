//
//  MaxPlanDetailScreen.swift
//  InterestCalculator
//
//  Max planının detayı: toplam net kazanç, banka banka yatırılacak tutar ve
//  kademe payı, dağıtılmayan tutar, para ayrılmayan bankalar ve toplamlar.
//  Yalnız kayıttaki değerleri gösterir — hesap YAPMAZ; bankalar sonradan değişse
//  de hesap anındaki plan görünür.
//

import SwiftUI

struct MaxPlanDetailScreen: View {
    let record: MaxPlanRecord
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    private var plan: MaxPlan { record.plan }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                if let comparison {
                    comparisonBadge(comparison)
                }
                if plan.allocations.isEmpty {
                    noEarningsCard
                } else {
                    sectionTitle("Dağılım")
                    ForEach(Array(plan.allocations.enumerated()), id: \.element.id) { index, allocation in
                        allocationCard(allocation)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("maxAllocation_\(index)")
                    }
                }
                if plan.unallocated > 0 {
                    unallocatedCard
                }
                if !plan.unusedBanks.isEmpty {
                    unusedCard
                }
                totalsCard
                notes
                disclaimer
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.snowfield.ignoresSafeArea())
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("maxDetailRoot")
    }

    // MARK: - Özet

    private var heroCard: some View {
        VStack(spacing: 6) {
            Text(moneyText(plan.totalNet))
                .font(dynamicTypeSize.isAccessibilitySize
                      ? .system(.largeTitle, design: .rounded).weight(.semibold)
                      : .system(size: heroSize, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospacedDigit()
                .foregroundStyle(plan.totalNet > 0 ? Color.aurora : Color.slate)
            Text("\(plan.nights) günlük toplam net kazanç")
                .font(.subheadline)
                .foregroundStyle(.slate)
            Text("\(moneyText(plan.amount)) · \(dateText(record.startDate)) → \(dateText(endDate))")
                .font(.footnote)
                .foregroundStyle(.slate)
                .monospacedDigit()
            Text("Hesaplandı: \(record.createdAt.formatted(date: .long, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.slate)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .cardSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("maxDetailTotalNet")
    }

    /// Planın, aynı kurallarla tek bankaya konan en iyi seçeneğe göre fazlası.
    /// Plan zaten tek banka kullanıyorsa ya da fazlası yoksa gösterilmez.
    private var comparison: (baseline: MaxPlan.Baseline, gain: Money)? {
        guard plan.allocations.count > 1, let baseline = plan.bestSingleBank else { return nil }
        let gain = plan.totalNet - baseline.netInterest
        return gain > 0 ? (baseline, gain) : nil
    }

    private func comparisonBadge(_ comparison: (baseline: MaxPlan.Baseline, gain: Money)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.right.circle.fill")
                .foregroundStyle(.aurora)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bölmek \(moneyText(comparison.gain)) daha fazla kazandırıyor")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                Text("Tek bankada en iyisi \(comparison.baseline.bankName): \(moneyText(comparison.baseline.deposit)) ile \(moneyText(comparison.baseline.netInterest)) net.")
                    .font(.caption)
                    .foregroundStyle(.slate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.frost))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dağılım

    private func allocationCard(_ allocation: MaxPlan.Allocation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(allocation.bankName)
                        .font(.headline)
                        .foregroundStyle(.ink)
                    Text(MaxPlanText.rateCaption(percent: allocation.annualRatePercent,
                                                 isNet: allocation.rateIsNet))
                        .font(.caption)
                        .foregroundStyle(.slate)
                }
                Spacer()
                Text(shareText(allocation.deposit))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.slate)
                    .monospacedDigit()
            }
            Text(moneyText(allocation.deposit))
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ruleBadge(MaxPlanText.rule(for: allocation),
                      systemImage: allocation.tier == nil ? "building.columns" : "stairs")

            hairline
            moneyRow("Vadesiz kalan", allocation.idleAmount)
            moneyRow("Faize giren", allocation.interestBearing)
            if allocation.excessAboveCap > 0 {
                moneyRow("Limit üstü (faizsiz)", allocation.excessAboveCap)
            }
            moneyRow("\(plan.nights) günlük net kazanç", allocation.netInterest, emphasized: true)
            moneyRow("Vade sonu bakiye", allocation.finalBalance)

            if let headroom = allocation.headroom, let upper = allocation.tier?.upperBound {
                hairline
                moneyRow("Üst kademeye (\(upper.grouped(fractionDigits: 0)) ₺) kalan", headroom)
                if let oneDay = allocation.oneDayNet {
                    Text("Hedef pay: 1 günlük net faiz \(moneyText(oneDay)) × %\(bufferText) = \(moneyText(oneDay * plan.bufferPercent / 100))")
                        .font(.caption)
                        .foregroundStyle(.slate)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func ruleBadge(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.glacier)
            Text(text).font(.subheadline).foregroundStyle(.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.frost))
    }

    private var noEarningsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kazanç sağlayan bir dağılım bulunamadı")
                .font(.headline)
                .foregroundStyle(.ink)
            Text("Bu tutar ve sürede hiçbir banka net kazanç sağlamıyor. Düzenle'deki oranları ve vadesiz şartlarını kontrol edin.")
                .font(.footnote)
                .foregroundStyle(.slate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var unallocatedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dağıtılmayan")
                    .font(.headline)
                    .foregroundStyle(.ink)
                Spacer()
                Text(moneyText(plan.unallocated))
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.ink)
                    .monospacedDigit()
            }
            Text("Bu tutar hiçbir bankaya kazancı artırarak eklenemiyor; örneğin eklendiği banka üst kademeye geçip daha fazla vadesiz tutmayı gerektiriyor. Vadesiz bir hesapta tutabilirsiniz.")
                .font(.footnote)
                .foregroundStyle(.slate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("maxUnallocated")
    }

    private var unusedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Para ayrılmayan bankalar")
                .font(.headline)
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(plan.unusedBanks) { bank in
                HStack {
                    Text(bank.name).foregroundStyle(.ink)
                    Spacer()
                    Text(MaxPlanText.rateCaption(percent: bank.annualRatePercent, isNet: bank.rateIsNet))
                        .foregroundStyle(.slate)
                }
                .font(.subheadline)
            }
            Text("Bu tutar ve sürede bu bankalara para ayırmak toplam kazancı artırmıyor.")
                .font(.caption)
                .foregroundStyle(.slate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Toplamlar

    private var totalsCard: some View {
        VStack(spacing: 10) {
            moneyRow("Yatırılan", plan.totalDeposited)
            if plan.unallocated > 0 {
                moneyRow("Dağıtılmayan", plan.unallocated)
            }
            hairline
            moneyRow("Brüt faiz", plan.totalGross)
            deductionRow("Stopaj (%\(plan.withholdingPercent.grouped(fractionDigits: 0...2)))", plan.totalDeductions)
            hairline
            moneyRow("Net kazanç (\(plan.nights) gün)", plan.totalNet, emphasized: true)
            moneyRow("Vade sonu toplam", plan.amount + plan.totalNet)
        }
        .padding(16)
        .cardSurface()
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
        let valueText = Text("− " + moneyText(value))
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

    // MARK: - Notlar + disclaimer

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            noteText("Kademeli bankalarda tutar, vade sonunda üst kademeye geçmeyecek şekilde seçilir; sınıra en az vade sonu bakiyesinin 1 günlük net faizi × %\(bufferText) kadar pay kalır.")
            noteText("Plan hesap günü başlar. Hafta içi kazanç ertesi gün, hafta sonu (Cuma–Pazar) kazancı Pazartesi valörüyle bakiyeye eklenip bileşiklenir.")
            noteText("Vadesiz kalan ve faize giren tutarlar başlangıç değerleridir. Bankalar ve stopaj hesap anındaki Düzenle değerleridir; sonraki değişiklikler bu planı değiştirmez.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.slate)
    }

    private var disclaimer: some View {
        Text(ResultMessages.disclaimer)
            .font(.footnote)
            .foregroundStyle(.slate)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Biçim yardımcıları

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
    }

    private var endDate: Date {
        AccrualCalendar.addNights(plan.nights, to: record.startDate)
    }

    private var bufferText: String {
        plan.bufferPercent.grouped(fractionDigits: 0...2)
    }

    /// Toplam tutar içindeki pay: "%16,3".
    private func shareText(_ deposit: Money) -> String {
        guard plan.amount > 0 else { return "" }
        return "%" + (deposit * 100 / plan.amount).grouped(fractionDigits: 0...1)
    }

    private func moneyText(_ value: Money) -> String {
        value.formatted(.currency(code: "TRY"))
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private var hairline: some View {
        Rectangle().fill(Color.rime).frame(height: 1 / displayScale)
    }
}

#Preview {
    let banks = AppState.preview.planningConditions
    let plan = MaxPlanner.plan(amount: 152_000, banks: banks, withholding: .single(.percent(17.5)),
                               nights: 10, startWeekday: .monday)
    NavigationStack {
        MaxPlanDetailScreen(record: MaxPlanRecord(id: UUID(), createdAt: Date(),
                                                  startDate: AccrualCalendar.today(), plan: plan))
    }
}
