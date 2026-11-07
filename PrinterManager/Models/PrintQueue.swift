import Foundation

/// Baskı sırasındaki bir adım: belgenin bir sayfası, kağıdın bir yüzü.
struct PrintStep: Identifiable, Equatable {
    enum Side: Equatable {
        /// Tek yüzlü baskı
        case single
        /// Çift yönde kağıdın ön yüzü (tek sayfalar)
        case front
        /// Çift yönde kağıdın arka yüzü (çift sayfalar, kağıtlar çevrildikten sonra)
        case back
        
        var title: String {
            switch self {
            case .single: return "Tek yüz"
            case .front: return "Ön yüz"
            case .back: return "Arka yüz"
            }
        }
    }
    
    enum State: Equatable {
        case pending
        case printing
        case printed
        /// Kağıt bozuldu; sayfa (ya da kağıt) yeniden basılıyor
        case spoiled
        /// Basılmadı (kağıdı bozuldu ya da kullanıcı atladı)
        case skipped
        
        var isFinished: Bool {
            self != .pending && self != .printing
        }
    }
    
    let id = UUID()
    /// 0'dan başlar; belgenin sayfa sayısına eşit ya da büyükse çift yön için boş sayfa
    let pageIndex: Int
    let side: Side
    /// Geçiş numarası (PrintPass.id)
    let pass: Int
    var state: State = .pending
    /// Bozulan bir sayfanın ya da kağıdın yeniden basımı
    var isReprint = false
    /// Listede gösterilen kısa açıklama
    var note: String?
    
    var pageNumber: Int { pageIndex + 1 }
}

/// Aralarında kağıtların çevrildiği ya da yeniden yüklendiği baskı geçişi
struct PrintPass: Identifiable, Equatable {
    enum Kind: Equatable {
        case single
        case fronts
        case backs
        case reprintSingle
        case reprintFronts
        case reprintBacks
        
        var isBacks: Bool { self == .backs || self == .reprintBacks }
        var isReprint: Bool { self == .reprintSingle || self == .reprintFronts || self == .reprintBacks }
    }
    
    let id: Int
    let kind: Kind
    
    var title: String {
        switch kind {
        case .single: return "Sayfalar"
        case .fronts: return "Ön yüzler (tek sayfalar)"
        case .backs: return "Arka yüzler (çift sayfalar, ters sırada)"
        case .reprintSingle: return "Yeniden basım"
        case .reprintFronts: return "Yeniden basım: ön yüzler"
        case .reprintBacks: return "Yeniden basım: arka yüzler"
        }
    }
    
    /// Geçişten önce kullanıcının yapacağı iş
    var preparation: String? {
        switch kind {
        case .single, .fronts: return nil
        case .backs, .reprintBacks: return "Kağıtları çevirip yükleyin"
        case .reprintSingle, .reprintFronts: return "Tepsiye boş kağıt koyun"
        }
    }
}

/// Baskı sırası: geçişler, adımlar ve müdahaleler (tekrar yazdır, çift kağıt...).
/// Sırayı yöneten mantık burada; PrintManager adımları sırayla basar.
struct PrintQueue: Equatable {
    private(set) var passes: [PrintPass] = []
    private(set) var steps: [PrintStep] = []
    /// Belgedeki sayfa sayısı (boş sayfa hariç)
    private(set) var documentPageCount = 0
    let isDuplex: Bool
    
    init(documentPageCount: Int, sheetPageCount: Int, duplex: Bool) {
        self.documentPageCount = documentPageCount
        self.isDuplex = duplex
        
        if duplex {
            // Önce tek sayfalar (1, 3, 5...), çevirince çift sayfalar ters sırada (..., 6, 4, 2)
            passes = [PrintPass(id: 0, kind: .fronts), PrintPass(id: 1, kind: .backs)]
            steps = stride(from: 0, to: sheetPageCount, by: 2).map {
                PrintStep(pageIndex: $0, side: .front, pass: 0)
            }
            steps += stride(from: 1, to: sheetPageCount, by: 2).reversed().map {
                PrintStep(pageIndex: $0, side: .back, pass: 1)
            }
        } else {
            passes = [PrintPass(id: 0, kind: .single)]
            steps = (0..<sheetPageCount).map { PrintStep(pageIndex: $0, side: .single, pass: 0) }
        }
    }
    
    // MARK: - Reading
    
    func pass(_ id: Int) -> PrintPass? {
        passes.first { $0.id == id }
    }
    
    func step(_ id: UUID) -> PrintStep? {
        steps.first { $0.id == id }
    }
    
    /// Basılacak sonraki adım (geçiş sırasına göre)
    var nextPendingStep: PrintStep? {
        for pass in passes {
            if let step = steps.first(where: { $0.pass == pass.id && $0.state == .pending }) {
                return step
            }
        }
        return nil
    }
    
    func hasPending(inPass pass: Int) -> Bool {
        steps.contains { $0.pass == pass && $0.state == .pending }
    }
    
    func steps(inPass pass: Int) -> [PrintStep] {
        steps.filter { $0.pass == pass }
    }
    
    /// Adımların baskı sırasındaki numarası (atlananlar numara almaz)
    var printOrder: [UUID: Int] {
        var order: [UUID: Int] = [:]
        var number = 0
        for pass in passes {
            for step in steps where step.pass == pass.id && step.state != .skipped {
                number += 1
                order[step.id] = number
            }
        }
        return order
    }
    
    var finishedCount: Int { steps.filter { $0.state.isFinished }.count }
    var pendingCount: Int { steps.filter { $0.state == .pending }.count }
    
    func isBlank(_ step: PrintStep) -> Bool {
        step.pageIndex >= documentPageCount
    }
    
    // MARK: - Engine
    
    mutating func setState(_ state: PrintStep.State, for id: UUID, note: String? = nil) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].state = state
        if let note = note {
            steps[index].note = note
        }
    }
    
    /// Yazdırılırken kullanıcı başka bir durum vermediyse basıldı say
    mutating func finishPrinting(_ id: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == id }), steps[index].state == .printing else { return }
        steps[index].state = .printed
    }
    
    /// Geçişteki bekleyen adımları atla (kullanıcı yeniden basımı istemedi)
    mutating func skipPending(inPass pass: Int, note: String) {
        for index in steps.indices where steps[index].pass == pass && steps[index].state == .pending {
            steps[index].state = .skipped
            steps[index].note = note
        }
    }
    
    // MARK: - Interventions
    
    enum Action: Equatable {
        /// Aynı sayfayı hemen yeniden bas (ön yüz / tek yüz, şu anki sayfa)
        case reprintNow
        /// Kağıt bozuk: kağıdı (çift yönde iki yüzüyle) en sonda yeniden bas
        case spoilSheet
        /// Arka yüz basılırken iki kağıt çekildi: bu ve yığındaki sonraki kağıt bozuk
        case doubleFeed
        
        var title: String {
            switch self {
            case .reprintNow: return "Tekrar Yazdır"
            case .spoilSheet: return "Kağıt Bozuk, Sona Ekle"
            case .doubleFeed: return "Çift Kağıt Çekti"
            }
        }
        
        var symbol: String {
            switch self {
            case .reprintNow: return "arrow.counterclockwise"
            case .spoilSheet: return "arrow.uturn.down"
            case .doubleFeed: return "doc.on.doc"
            }
        }
    }
    
    /// Adımda kullanılabilecek müdahaleler
    func actions(for id: UUID, currentStepID: UUID?) -> [Action] {
        guard let step = step(id), step.state == .printing || step.state == .printed else { return [] }
        let isCurrent = step.id == currentStepID
        
        switch step.side {
        case .single:
            return [.reprintNow]
        case .front:
            // Şu anki ön yüz hemen yeniden basılabilir (yığın sırası bozulmaz);
            // önceki bir ön yüz için kağıdı sona eklemek gerekir
            return isCurrent ? [.reprintNow, .spoilSheet] : [.spoilSheet]
        case .back:
            return isCurrent ? [.doubleFeed, .spoilSheet] : [.spoilSheet]
        }
    }
    
    /// Müdahaleyi uygular; günlük için açıklama döndürür
    mutating func apply(_ action: Action, to id: UUID) -> String? {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return nil }
        let step = steps[index]
        
        switch action {
        case .reprintNow:
            steps[index].state = .spoiled
            steps[index].note = "Hatalı, hemen yeniden basılıyor"
            var copy = PrintStep(pageIndex: step.pageIndex, side: step.side, pass: step.pass)
            copy.isReprint = true
            copy.note = "Tekrar"
            steps.insert(copy, at: index + 1)
            return "Sayfa \(step.pageNumber) hemen yeniden basılacak. Hatalı çıkan kağıdı atın."
        
        case .spoilSheet:
            if step.side == .single {
                steps[index].state = .spoiled
                steps[index].note = "Bozuk, en sonda yeniden basılacak"
                addReprint(sheets: [(step.pageIndex, nil)])
                return "Sayfa \(step.pageNumber) en sonda yeniden basılacak. Bozuk kağıdı ayırın."
            }
            let sheet = sheetPages(for: step)
            spoil(sheet: sheet, reason: "Kağıt bozuk, en sonda yeniden basılacak")
            addReprint(sheets: [sheet])
            return "Sayfa \(sheet.front + 1)/\(sheet.back.map { String($0 + 1) } ?? "-") kağıdı en sonda iki yüzüyle yeniden basılacak. Bozuk kağıdı yığından çıkarın."
        
        case .doubleFeed:
            guard step.side == .back else { return nil }
            var sheets = [sheetPages(for: step)]
            spoil(sheet: sheets[0], reason: "Çift kağıt çekti, en sonda yeniden basılacak")
            
            // Yığındaki sonraki kağıt da çekildi: onun arka yüzü artık yanlış kağıda basılırdı
            if let next = steps.first(where: { $0.pass == step.pass && $0.state == .pending && $0.side == .back }) {
                let nextSheet = sheetPages(for: next)
                spoil(sheet: nextSheet, reason: "Kağıdı çift çekildi, en sonda yeniden basılacak")
                sheets.append(nextSheet)
            }
            addReprint(sheets: sheets)
            let list = sheets.map { "\($0.front + 1)/\(($0.back ?? $0.front) + 1)" }.joined(separator: " ve ")
            return "Çift kağıt: \(list) kağıtları en sonda iki yüzüyle yeniden basılacak. Bu kağıtları atın."
        }
    }
    
    // MARK: - Private
    
    /// Arka yüzün kağıdı: ön yüz bir önceki sayfa
    private func sheetPages(for step: PrintStep) -> (front: Int, back: Int?) {
        switch step.side {
        case .single: return (step.pageIndex, nil)
        case .front: return (step.pageIndex, step.pageIndex + 1)
        case .back: return (step.pageIndex - 1, step.pageIndex)
        }
    }
    
    /// Kağıdın bu geçişlerdeki adımlarını bozuk / atlandı işaretle
    private mutating func spoil(sheet: (front: Int, back: Int?), reason: String) {
        for index in steps.indices {
            let page = steps[index].pageIndex
            guard page == sheet.front || page == sheet.back, !steps[index].isReprintTarget else { continue }
            switch steps[index].state {
            case .printing, .printed:
                steps[index].state = .spoiled
                steps[index].note = reason
            case .pending:
                steps[index].state = .skipped
                steps[index].note = reason
            case .spoiled, .skipped:
                break
            }
        }
    }
    
    /// Kağıtları henüz başlamamış bir yeniden basım geçişine ekler, yoksa yenisini açar.
    /// Çift yönde ön yüzler artan sırada, arka yüzler ters sırada basılır.
    private mutating func addReprint(sheets newSheets: [(front: Int, back: Int?)]) {
        let duplexSheets = newSheets.contains { $0.back != nil }
        let frontsKind: PrintPass.Kind = duplexSheets ? .reprintFronts : .reprintSingle
        
        // Başlamamış (hepsi bekleyen) son yeniden basım geçişini kullan
        var frontsPass = passes.last(where: { $0.kind == frontsKind }).flatMap { pass -> PrintPass? in
            let passSteps = steps(inPass: pass.id)
            return passSteps.allSatisfy { $0.state == .pending } ? pass : nil
        }
        if frontsPass == nil {
            let id = (passes.map(\.id).max() ?? -1) + 1
            frontsPass = PrintPass(id: id, kind: frontsKind)
            passes.append(frontsPass!)
            if duplexSheets {
                passes.append(PrintPass(id: id + 1, kind: .reprintBacks))
            }
        }
        guard let fronts = frontsPass else { return }
        let backsID = fronts.id + 1
        
        // Geçişteki kağıtları topla, yenileri ekle, sırayı yeniden kur
        var sheets = steps(inPass: fronts.id).map { step -> (front: Int, back: Int?) in
            (step.pageIndex, duplexSheets ? step.pageIndex + 1 : nil)
        }
        for sheet in newSheets where !sheets.contains(where: { $0.front == sheet.front }) {
            sheets.append(sheet)
        }
        sheets.sort { $0.front < $1.front }
        steps.removeAll { $0.pass == fronts.id || (duplexSheets && $0.pass == backsID) }
        
        for sheet in sheets {
            var step = PrintStep(pageIndex: sheet.front, side: duplexSheets ? .front : .single, pass: fronts.id)
            step.isReprint = true
            step.note = "Yeniden basım"
            steps.append(step)
        }
        if duplexSheets {
            for sheet in sheets.reversed() {
                guard let back = sheet.back else { continue }
                var step = PrintStep(pageIndex: back, side: .back, pass: backsID)
                step.isReprint = true
                step.note = "Yeniden basım"
                steps.append(step)
            }
        }
    }
}

private extension PrintStep {
    /// Yeniden basım geçişlerindeki bekleyen adımlar bozuk işaretlemesinden etkilenmesin
    var isReprintTarget: Bool {
        isReprint && state == .pending
    }
}
