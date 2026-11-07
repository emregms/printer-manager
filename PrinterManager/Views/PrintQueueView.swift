import SwiftUI

/// Baskı sırası: hangi sayfa basıldı, hangisi basılıyor, sırada ne var.
/// Şu anki sayfaya anında müdahale (tekrar yazdır, çift kağıt, kağıt bozuk).
struct PrintQueueView: View {
    @EnvironmentObject var printManager: PrintManager
    /// Sayfa numarası (1'den) → küçük resim
    let thumbnails: [Int: NSImage]
    
    var body: some View {
        if let queue = printManager.queue {
            VStack(spacing: 0) {
                if printManager.isPrinting, let step = printManager.currentStep {
                    CurrentStepBar(step: step, thumbnail: thumbnail(for: step, in: queue))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else if let message = printManager.lastIntervention {
                    InterventionBanner(message: message, canUndo: false)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                
                let order = queue.printOrder
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                            ForEach(Array(queue.passes.enumerated()), id: \.element.id) { index, pass in
                                Section {
                                    if index > 0, let preparation = pass.preparation {
                                        PreparationRow(text: preparation, isDone: hasStarted(pass, in: queue))
                                    }
                                    ForEach(queue.steps(inPass: pass.id)) { step in
                                        StepRow(
                                            step: step,
                                            order: order[step.id],
                                            thumbnail: thumbnail(for: step, in: queue),
                                            isBlank: queue.isBlank(step),
                                            isCurrent: step.id == printManager.currentStepID,
                                            actions: printManager.actions(for: step)
                                        )
                                        .id(step.id)
                                    }
                                } header: {
                                    PassHeader(pass: pass, steps: queue.steps(inPass: pass.id))
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .onChange(of: printManager.currentStepID) { id in
                        guard let id = id else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onAppear {
                        if let id = printManager.currentStepID {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    private func thumbnail(for step: PrintStep, in queue: PrintQueue) -> NSImage? {
        queue.isBlank(step) ? nil : thumbnails[step.pageNumber]
    }
    
    private func hasStarted(_ pass: PrintPass, in queue: PrintQueue) -> Bool {
        queue.steps(inPass: pass.id).contains { $0.state != .pending && $0.state != .skipped }
    }
}

// MARK: - Current Step

/// Şu an basılan sayfa ve anında müdahale düğmeleri
private struct CurrentStepBar: View {
    @EnvironmentObject var printManager: PrintManager
    let step: PrintStep
    let thumbnail: NSImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PageThumb(image: thumbnail, isBlank: thumbnail == nil, width: 44)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Şu an")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text("Sayfa \(step.pageNumber)")
                            .font(.title3.bold())
                        SideChip(side: step.side)
                        if step.isReprint {
                            Text("Tekrar")
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                        }
                    }
                    Text(hint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 8)
            }
            
            let actions = printManager.actions(for: step)
            if !actions.isEmpty || printManager.canUndoIntervention {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        Button {
                            printManager.intervene(action, on: step)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                        .buttonStyle(.bordered)
                        .tint(action == .doubleFeed ? .red : (action == .reprintNow ? .accentColor : .orange))
                        .help(help(for: action))
                    }
                    
                    Spacer()
                    
                    if printManager.canUndoIntervention {
                        Button {
                            printManager.undoIntervention()
                        } label: {
                            Label("Geri Al", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            if let message = printManager.lastIntervention {
                InterventionBanner(message: message, canUndo: printManager.canUndoIntervention)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }
    
    private var hint: String {
        switch step.side {
        case .single:
            return "Sayfa bozuk çıktıysa \"Tekrar Yazdır\": hemen yeniden basılır."
        case .front:
            return "Bozuk çıktıysa \"Tekrar Yazdır\". Çift kağıt çektiyse boş çıkan kağıdı tepsiye geri koyun."
        case .back:
            return "İki kağıt birden çekildiyse \"Çift Kağıt Çekti\": bu ve sonraki kağıt en sonda iki yüzüyle yeniden basılır."
        }
    }
    
    private func help(for action: PrintQueue.Action) -> String {
        switch action {
        case .reprintNow:
            return "Bu sayfayı hemen, sıradaki olarak yeniden basar"
        case .spoilSheet:
            return "Bu kağıdı bozuk sayar; seri bitince yeniden basar"
        case .doubleFeed:
            return "Bu ve yığındaki sonraki kağıt bozuk: sonraki arka yüz atlanır, iki kağıt en sonda yeniden basılır"
        }
    }
}

private struct InterventionBanner: View {
    let message: String
    let canUndo: Bool
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }
}

// MARK: - Rows

private struct PassHeader: View {
    let pass: PrintPass
    let steps: [PrintStep]
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(pass.kind.isReprint ? .orange : .accentColor)
            Text(pass.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(steps.filter { $0.state.isFinished }.count) / \(steps.count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var icon: String {
        switch pass.kind {
        case .single: return "doc.text"
        case .fronts: return "doc.text"
        case .backs: return "arrow.uturn.left.square"
        case .reprintSingle, .reprintFronts, .reprintBacks: return "arrow.counterclockwise.circle"
        }
    }
}

private struct PreparationRow: View {
    let text: String
    let isDone: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                .foregroundColor(isDone ? .green : .orange)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(isDone ? .secondary : .primary)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundColor(.secondary.opacity(0.4))
        )
    }
}

private struct StepRow: View {
    @EnvironmentObject var printManager: PrintManager
    let step: PrintStep
    let order: Int?
    let thumbnail: NSImage?
    let isBlank: Bool
    let isCurrent: Bool
    let actions: [PrintQueue.Action]
    
    var body: some View {
        HStack(spacing: 10) {
            Text(order.map(String.init) ?? "–")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .trailing)
            
            PageThumb(image: thumbnail, isBlank: isBlank, width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isBlank ? "Boş sayfa" : "Sayfa \(step.pageNumber)")
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .strikethrough(step.state == .skipped)
                    SideChip(side: step.side)
                }
                if let note = step.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 6)
            
            StateChip(state: step.state)
            
            // Önceki sayfalar için müdahale menüsü (şu anki sayfanınkiler üstte)
            if !isCurrent && !actions.isEmpty {
                Menu {
                    ForEach(actions, id: \.self) { action in
                        Button {
                            printManager.intervene(action, on: step)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Bu sayfa bozuk çıktıysa")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .opacity(step.state == .skipped ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.2), value: step.state)
    }
}

// MARK: - Pieces

struct PageThumb: View {
    let image: NSImage?
    let isBlank: Bool
    let width: CGFloat
    
    var body: some View {
        let height = width * 1.414
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isBlank {
                Color.white
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    )
            } else {
                Color.secondary.opacity(0.1)
            }
        }
        .frame(width: width, height: height)
        .background(Color.white)
        .cornerRadius(3)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

private struct SideChip: View {
    let side: PrintStep.Side
    
    var body: some View {
        if side != .single {
            Text(side.title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill((side == .front ? Color.blue : Color.purple).opacity(0.15)))
                .foregroundColor(side == .front ? .blue : .purple)
        }
    }
}

private struct StateChip: View {
    let state: PrintStep.State
    
    var body: some View {
        HStack(spacing: 4) {
            if state == .printing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }
    
    private var title: String {
        switch state {
        case .pending: return "Bekliyor"
        case .printing: return "Basılıyor"
        case .printed: return "Basıldı"
        case .spoiled: return "Bozuk"
        case .skipped: return "Atlandı"
        }
    }
    
    private var symbol: String {
        switch state {
        case .pending: return "hourglass"
        case .printing: return "printer.fill"
        case .printed: return "checkmark.circle.fill"
        case .spoiled: return "arrow.uturn.down.circle.fill"
        case .skipped: return "minus.circle"
        }
    }
    
    private var color: Color {
        switch state {
        case .pending: return .secondary
        case .printing: return .accentColor
        case .printed: return .green
        case .spoiled: return .orange
        case .skipped: return .secondary
        }
    }
}
