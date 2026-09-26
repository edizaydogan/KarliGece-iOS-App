//
//  MaxPlanner.swift
//  InterestCalculator
//
//  Max sekmesinin hesabı: bir tutarı kayıtlı bankalara, N günün sonunda en
//  yüksek TOPLAM net kazancı verecek şekilde böler. Saf, deterministik; faiz
//  matematiği YAZMAZ — her tutarın kazancı mevcut `CompoundingEngine.project`
//  çağrısıdır (tek doğruluk kaynağı). Date'e dokunmaz; başlangıç günü dışarıdan
//  gelir (Karşılaştır gibi bugünden başlar, hafta sonu snap'i yok).
//
//  Kademe kuralı (kullanıcı tanımı): kademeli bir bankada bakiye N. günün
//  sonunda ÜST kademeye geçmemeli. Kademenin tepesine yatırılan tutar, vade
//  sonunda sınıra "vade sonu bakiyesinin 1 günlük net faizi × `buffer`"
//  (varsayılan %10) kadar pay kalacak şekilde seçilir — sınırı geçmeye bir
//  günlük faizden az kalır.
//
//  Yöntem:
//   1. Her banka için kademe başına bir SEÇENEK, yani yatırılabilecek
//      [en az, en çok] aralığı. En az = kademenin alt sınırı (sabit vadesiz
//      şartında şart tutarı da — altı hiç faize girmez); en çok = vade sonunda
//      sınıra pay kalan en büyük tutar (motorla, kuruş hassasiyetinde ikili
//      arama). Son kademe sınırsızdır.
//   2. Aralık içinde kazanç tutarla doğrusaldır (sabit şartta faize giren =
//      tutar − şart; bileşik büyüme de tutarla orantılı). Eğim motordan iki
//      noktayla ölçülür. Faize giren tavanı (limit) varsa eğri orada kırılır.
//   3. Her banka için bir seçenek ya da "kullanma" seçilerek tüm kombinasyonlar
//      denenir: önce alt sınırlar yatırılır, kalan para en yüksek eğimli
//      parçadan başlayarak doldurulur (doğrusal programın açgözlü çözümü).
//      Hiçbir yere kazancı artırarak sığmayan para DAĞITILMAZ.
//   4. En iyi kombinasyonun tutarları motorla yeniden hesaplanır.
//

import Foundation

nonisolated enum MaxPlanner {

    /// Kademe sınırına bırakılan pay: vade sonu bakiyesindeki 1 günlük net
    /// faizin bu yüzdesi. Değişebilir diye tek yerde tutulur; her plana kaydedilir.
    static let defaultBuffer = Percentage.percent(10)

    /// Planlanabilecek gün aralığı (Özet'in vade üst sınırıyla aynı).
    static let dayRange = 1...365

    /// `amount` tutarını `banks` arasında, `startWeekday`'den başlayan `nights`
    /// gecenin sonunda toplam net kazancı en yüksek olacak şekilde böler.
    static func plan(
        amount: Money,
        banks: [BankCondition],
        withholding: WithholdingRule,
        nights: Int,
        startWeekday: Weekday,
        buffer: Percentage = defaultBuffer
    ) -> MaxPlan {
        let context = Context(
            amount: max(0, floorToKurus(amount)),
            nights: min(max(nights, dayRange.lowerBound), dayRange.upperBound),
            startWeekday: startWeekday,
            withholding: withholding,
            buffer: buffer.clampedToNonNegative()
        )
        let options = banks.map { self.options(for: $0, context) }
        let order = segmentOrder(options)
        let choice = search(options, order: order, amount: context.amount)
        let deposits = fill(choice, options, order: order, amount: context.amount)?.deposits
            ?? banks.map { _ in 0 }

        var allocations: [MaxPlan.Allocation] = []
        var unused: [MaxPlan.BankRef] = []
        for (bank, condition) in banks.enumerated() {
            guard let index = choice[bank], deposits[bank] > 0 else {
                unused.append(reference(condition))
                continue
            }
            allocations.append(allocation(condition, option: options[bank][index],
                                          deposit: deposits[bank], context))
        }
        let deposited = allocations.reduce(Money(0)) { $0 + $1.deposit }

        return MaxPlan(
            amount: context.amount,
            nights: context.nights,
            bufferPercent: context.buffer.percentValue,
            withholdingPercent: withholding.lines.reduce(Decimal(0)) { $0 + $1.rate.percentValue },
            allocations: allocations,
            unusedBanks: unused,
            unallocated: context.amount - deposited,
            bestSingleBank: bestSingleBank(banks, options, order: order, context)
        )
    }

    // MARK: - Model

    private nonisolated struct Context {
        var amount: Money
        var nights: Int
        var startWeekday: Weekday
        var withholding: WithholdingRule
        var buffer: Percentage
    }

    /// Bir bankanın tek kademesinde yatırılabilecek aralık ve kazanç eğrisi.
    private nonisolated struct Option {
        var tier: MaxPlan.Tier?
        var idleRule: MaxPlan.IdleRule
        /// Bu kademede olmak (ve kazanmak) için en az yatırılacak tutar.
        var minimum: Money
        /// `minimum`'daki N günlük net kazanç (motordan, kesin).
        var baseNet: Money
        /// `minimum`'dan sonraki parçalar, eğimi azalan sırada.
        var segments: [Segment]
    }

    /// Kazanç eğrisinin doğrusal bir parçası.
    private nonisolated struct Segment {
        /// Parçanın genişliği; nil = sınırsız (son kademe).
        var length: Money?
        /// TL başına N günlük net kazanç.
        var slope: Decimal
    }

    /// Eğim sırasındaki bir parçanın adresi.
    private nonisolated struct SegmentRef {
        var bank: Int
        var option: Int
        var segment: Int
        var slope: Decimal
    }

    // MARK: - Seçenekler

    private static func options(for condition: BankCondition, _ context: Context) -> [Option] {
        guard case .tiered(let table) = condition.idleRequirement else {
            return [option(condition, flat: condition, lower: 0, upper: nil, tier: nil, context)]
                .compactMap { $0 }
        }
        return table.tiers.indices.compactMap { index in
            let tier = table.tiers[index]
            let lower = index > 0 ? table.tiers[index - 1].upperBound : nil
            var flat = condition
            switch tier.value {
            case .percentage(let percentage): flat.idleRequirement = .percentage(percentage)
            case .fixedAmount(let amount):    flat.idleRequirement = .fixedAmount(amount)
            }
            return option(condition, flat: flat, lower: lower ?? 0, upper: tier.upperBound,
                          tier: MaxPlan.Tier(index: index, lowerBound: lower, upperBound: tier.upperBound),
                          context)
        }
    }

    /// Bir kademenin seçeneği; bu tutara ve vadeye sığmıyorsa nil.
    ///
    /// `flat`: kademenin şartı kademesiz hale getirilmiş koşul. Kademe içinde
    /// (sınır geçilmedikçe) asıl koşulla birebir aynı sonucu verir; eğim ölçümü
    /// için aralık dışındaki noktalarda da güvenle çağrılabilir.
    private static func option(
        _ condition: BankCondition,
        flat: BankCondition,
        lower: Money,
        upper: Money?,
        tier: MaxPlan.Tier?,
        _ context: Context
    ) -> Option? {
        // En az: kademe alt sınırı, en az bakiye şartı ve sabit vadesiz şartı
        // (şart tutarına kadar olan para hiç faize girmez).
        var minimum = max(0, lower)
        if let minBalance = flat.minTotalBalance {
            minimum = max(minimum, minBalance)
        }
        if case .fixedAmount(let idle) = flat.idleRequirement {
            minimum = max(minimum, idle)
        }
        minimum = ceilToKurus(minimum)
        guard minimum <= context.amount else { return nil }

        // En çok: sınırlı kademede vade sonunda sınıra pay kalan en büyük tutar.
        var maximum: Money?
        if let upper {
            guard let top = largestDeposit(below: upper, from: minimum, condition, context) else {
                return nil
            }
            maximum = top
        }

        // Kırılma noktaları: en az → (limit kırılması) → en çok / sınırsız.
        var points = [minimum]
        if let kink = capKink(flat).map(floorToKurus), kink > minimum,
           maximum.map({ kink < $0 }) ?? true {
            points.append(kink)
        }
        if let maximum, maximum > points[points.count - 1] {
            points.append(maximum)
        }

        let net = { (deposit: Money) in projection(deposit, flat, context).netInterest }
        let baseNet = net(minimum)
        var segments: [Segment] = []
        var previousNet = baseNet
        for (start, end) in zip(points, points.dropFirst()) {
            let endNet = net(end)
            segments.append(Segment(length: end - start, slope: (endNet - previousNet) / (end - start)))
            previousNet = endNet
        }
        if maximum == nil {
            // Sınırsız son parça: eğim, tutar genişliğinde bir ölçümle bulunur.
            let start = points[points.count - 1]
            let probe = start + max(context.amount, 1)
            segments.append(Segment(length: nil, slope: (net(probe) - previousNet) / (probe - start)))
        }
        // Eğri içbükeydir; kuruş gürültüsü eğim sırasını bozmasın (açgözlü
        // dolum bir seçeneğin parçalarının kendi sırasında dolmasına dayanır).
        for index in segments.indices {
            var slope = max(0, segments[index].slope)
            if index > 0 { slope = min(slope, segments[index - 1].slope) }
            segments[index].slope = slope
        }
        return Option(tier: tier, idleRule: idleRule(flat), minimum: minimum,
                      baseNet: baseNet, segments: segments)
    }

    /// Sınırlı kademede (`upper` DIŞLAYICI) vade sonunda sınıra en az pay kalan
    /// en büyük yatırım, kuruş hassasiyetinde; tutarı aşmaz. En az tutar bile
    /// sığmıyorsa nil (kademe bu vadeye dar).
    private static func largestDeposit(
        below upper: Money,
        from minimum: Money,
        _ condition: BankCondition,
        _ context: Context
    ) -> Money? {
        let highest = min(upper - kurus, context.amount)
        guard minimum <= highest, fits(minimum, below: upper, condition, context) else { return nil }
        if fits(highest, below: upper, condition, context) { return highest }

        // Değişmez: `low` sığar, `high` sığmaz. Vade sonu bakiyesi yatırılan
        // tutarla arttığı için yüklem tek yönlüdür.
        var low = minimum
        var high = highest
        while high - low > kurus {
            let middle = floorToKurus((low + high) / 2)
            if fits(middle, below: upper, condition, context) {
                low = middle
            } else {
                high = middle
            }
        }
        return low
    }

    /// Vade sonunda sınır geçilmemiş ve sınıra en az pay kalmış mı? Bakiye hiç
    /// azalmadığı için vade sonu sınırın altındaysa ara günler de altındadır.
    private static func fits(
        _ deposit: Money,
        below upper: Money,
        _ condition: BankCondition,
        _ context: Context
    ) -> Bool {
        let final = deposit + projection(deposit, condition, context).netInterest
        guard final < upper else { return false }
        return upper - final >= context.buffer.applied(to: oneNightNet(at: final, condition, context))
    }

    /// Faize giren tavanının (limit) dolduğu yatırım tutarı; limit yoksa nil.
    private static func capKink(_ flat: BankCondition) -> Money? {
        guard let cap = flat.maxInterestBearingAmount else { return nil }
        let safeCap = max(0, cap)
        switch flat.idleRequirement {
        case .none:
            return safeCap
        case .fixedAmount(let idle):
            return max(0, idle) + safeCap
        case .percentage(let percentage):
            let share = 1 - percentage.clampedToZeroThroughOneHundred().fraction
            return share > 0 ? safeCap / share : nil
        case .tiered:
            return nil   // `flat` kademeli olmaz
        }
    }

    // MARK: - Arama

    /// Tüm "banka başına bir seçenek ya da hiç" kombinasyonları, derinlik
    /// öncelikli; alt sınırlar toplamı tutarı aşan dallar budanır. Eşitlikte ilk
    /// bulunan kalır — "kullanma" önce denendiği için para gereksiz bölünmez.
    /// En az tutarı 0 olan bir seçeneği varsa banka için "kullanma" denenmez: o
    /// seçenek hiç doldurulmayarak aynı sonucu verir, doldurularak daha iyisini.
    private static func search(_ options: [[Option]], order: [SegmentRef], amount: Money) -> [Int?] {
        var choice = [Int?](repeating: nil, count: options.count)
        var best = choice
        var bestValue: Decimal = 0

        func visit(_ bank: Int, committed: Money) {
            guard bank < options.count else {
                if let value = fill(choice, options, order: order, amount: amount)?.value,
                   value > bestValue {
                    bestValue = value
                    best = choice
                }
                return
            }
            choice[bank] = nil
            if !options[bank].contains(where: { $0.minimum == 0 }) {
                visit(bank + 1, committed: committed)
            }
            for index in options[bank].indices
            where committed + options[bank][index].minimum <= amount {
                choice[bank] = index
                visit(bank + 1, committed: committed + options[bank][index].minimum)
            }
            choice[bank] = nil
        }
        visit(0, committed: 0)
        return best
    }

    /// Bir kombinasyonun tahmini toplam net kazancı ve bankalara yatırılacak
    /// tutarlar. Önce alt sınırlar yatırılır; kalan para eğimi en yüksek
    /// parçadan başlayarak doldurulur. Alt sınırlar tutarı aşıyorsa nil.
    private static func fill(
        _ choice: [Int?],
        _ options: [[Option]],
        order: [SegmentRef],
        amount: Money
    ) -> (value: Decimal, deposits: [Money])? {
        var deposits = [Money](repeating: 0, count: choice.count)
        var value: Decimal = 0
        var remaining = amount
        for (bank, index) in choice.enumerated() {
            guard let index else { continue }
            deposits[bank] = options[bank][index].minimum
            value += options[bank][index].baseNet
            remaining -= options[bank][index].minimum
        }
        guard remaining >= 0 else { return nil }

        for ref in order where choice[ref.bank] == ref.option {
            guard remaining > 0, ref.slope > 0 else { break }
            let segment = options[ref.bank][ref.option].segments[ref.segment]
            let take = segment.length.map { min($0, remaining) } ?? remaining
            deposits[ref.bank] += take
            value += take * ref.slope
            remaining -= take
        }
        return (value, deposits)
    }

    /// Tüm seçeneklerin parçaları, eğim azalan sırada. Eşitlikte banka, seçenek,
    /// parça sırası: sonuç deterministik ve bir seçeneğin parçaları kendi sırasında.
    private static func segmentOrder(_ options: [[Option]]) -> [SegmentRef] {
        var refs: [SegmentRef] = []
        for (bank, bankOptions) in options.enumerated() {
            for (option, candidate) in bankOptions.enumerated() {
                for (segment, part) in candidate.segments.enumerated() {
                    refs.append(SegmentRef(bank: bank, option: option, segment: segment, slope: part.slope))
                }
            }
        }
        return refs.sorted { lhs, rhs in
            if lhs.slope != rhs.slope { return lhs.slope > rhs.slope }
            return (lhs.bank, lhs.option, lhs.segment) < (rhs.bank, rhs.option, rhs.segment)
        }
    }

    /// Aynı kurallarla tüm tutar tek bankaya konsaydı en iyi sonuç (motordan).
    private static func bestSingleBank(
        _ banks: [BankCondition],
        _ options: [[Option]],
        order: [SegmentRef],
        _ context: Context
    ) -> MaxPlan.Baseline? {
        var best: (bank: Int, value: Decimal, deposit: Money)?
        for bank in banks.indices {
            for index in options[bank].indices {
                var choice = [Int?](repeating: nil, count: banks.count)
                choice[bank] = index
                guard let filled = fill(choice, options, order: order, amount: context.amount),
                      filled.deposits[bank] > 0,
                      best.map({ filled.value > $0.value }) ?? true else { continue }
                best = (bank, filled.value, filled.deposits[bank])
            }
        }
        guard let best else { return nil }
        return MaxPlan.Baseline(
            bankName: banks[best.bank].name,
            deposit: best.deposit,
            netInterest: projection(best.deposit, banks[best.bank], context).netInterest
        )
    }

    // MARK: - Sonuç

    private static func allocation(
        _ condition: BankCondition,
        option: Option,
        deposit: Money,
        _ context: Context
    ) -> MaxPlan.Allocation {
        let result = projection(deposit, condition, context)
        let final = deposit + result.netInterest
        var headroom: Money?
        var oneDayNet: Money?
        if let upper = option.tier?.upperBound {
            headroom = upper - final
            oneDayNet = oneNightNet(at: final, condition, context)
        }
        return MaxPlan.Allocation(
            bankID: condition.id,
            bankName: condition.name,
            annualRatePercent: annualRatePercent(condition),
            rateIsNet: condition.rateBasis == .net,
            idleRule: option.idleRule,
            tier: option.tier,
            deposit: deposit,
            idleAmount: result.idleAmount,
            interestBearing: result.interestBearingBalance,
            excessAboveCap: result.excessAboveCap,
            grossInterest: result.totalGrossInterest,
            deductions: result.totalDeductions,
            netInterest: result.netInterest,
            headroom: headroom,
            oneDayNet: oneDayNet
        )
    }

    private static func reference(_ condition: BankCondition) -> MaxPlan.BankRef {
        MaxPlan.BankRef(id: condition.id, name: condition.name,
                        annualRatePercent: annualRatePercent(condition),
                        rateIsNet: condition.rateBasis == .net)
    }

    private static func annualRatePercent(_ condition: BankCondition) -> Decimal {
        switch condition.rateRule {
        case .flat(let rate): return rate.percentValue
        }
    }

    private static func idleRule(_ flat: BankCondition) -> MaxPlan.IdleRule {
        switch flat.idleRequirement {
        case .none:                       return .none
        case .percentage(let percentage): return .percentage(percentage.percentValue)
        case .fixedAmount(let amount):    return .fixedAmount(amount)
        case .tiered:                     return .none   // `flat` kademeli olmaz
        }
    }

    // MARK: - Motor ve kuruş yardımcıları

    private static func projection(_ deposit: Money, _ condition: BankCondition,
                                   _ context: Context) -> InterestResult {
        CompoundingEngine.project(
            initialBalance: deposit,
            startWeekday: context.startWeekday,
            nights: context.nights,
            condition: condition,
            withholding: context.withholding
        )
    }

    /// Bir bakiyenin 1 gecelik net faizi — kademe payının tabanı.
    private static func oneNightNet(at balance: Money, _ condition: BankCondition,
                                    _ context: Context) -> Money {
        InterestEngine.calculate(
            InterestInput(totalBalance: balance, nights: 1, condition: condition,
                          withholding: context.withholding)
        ).netInterest
    }

    private static let kurus: Money = Decimal(1) / 100

    private static func floorToKurus(_ value: Money) -> Money { rounded(value, .down) }
    private static func ceilToKurus(_ value: Money) -> Money { rounded(value, .up) }

    private static func rounded(_ value: Money, _ mode: NSDecimalNumber.RoundingMode) -> Money {
        var input = value
        var result = Money()
        NSDecimalRound(&result, &input, 2, mode)
        return result
    }
}
