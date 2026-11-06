import Foundation

/// Kendi sürücümüz: bir PDF sayfasını Ghostscript ile rastera çevirir, foo2qpdl ile
/// Samsung CLP-300'ün anladığı QPDL (SPL-C) verisine dönüştürür.
///
/// Parametreler foo2zjs'in `foo2qpdl-wrapper` betiğinin CLP-300 + A4 için ürettiği
/// komutla aynı (`-z0 -p2`, renkte ICM modu: `bitcmyk` + `-c -B -A`).
/// Wrapper'ın yarım ton (WTS) önsözü eklenmiyor: Ghostscript 10'da PDF girdide etkisiz.
struct QPDLDriver {
    let tools: QPDLTools
    
    // MARK: - Public Methods
    
    /// PDF'in tek bir sayfasını ham QPDL dosyasına çevirir
    /// - Parameters:
    ///   - pdf: Orijinal PDF (PDFKit ile bölünmez; yazı tipleri ve kaynaklar korunur)
    ///   - page: 1'den başlayan sayfa numarası
    ///   - color: Renkli (`.zc`) ya da siyah-beyaz (`.zm`)
    ///   - output: Yazılacak ham dosya
    func renderPage(
        pdf: URL,
        page: Int,
        color: Bool,
        resolution: QPDLResolution,
        to output: URL
    ) async throws -> QPDLPage {
        let input = ["-dFirstPage=\(page)", "-dLastPage=\(page)", pdf.path]
        return try await run(input: input, color: color, resolution: resolution, output: output)
    }
    
    /// Çift yön için boş sayfa (kağıt geçer, toner harcanmaz)
    func renderBlankPage(resolution: QPDLResolution, to output: URL) async throws -> QPDLPage {
        return try await run(input: ["-c", "showpage"], color: false, resolution: resolution, output: output)
    }
    
    // MARK: - Private Methods
    
    private func run(input: [String], color: Bool, resolution: QPDLResolution, output: URL) async throws -> QPDLPage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let page = try runPipeline(input: input, color: color, resolution: resolution, output: output)
                    continuation.resume(returning: page)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// gs | foo2qpdl > output
    private func runPipeline(input: [String], color: Bool, resolution: QPDLResolution, output: URL) throws -> QPDLPage {
        let start = Date()
        let fileManager = FileManager.default
        
        // stderr dosyaya: pipe'ta okunmadan dolarsa süreçler kilitlenebilir
        let gsLogURL = output.appendingPathExtension("gs.log")
        let foo2qpdlLogURL = output.appendingPathExtension("foo2qpdl.log")
        for url in [output, gsLogURL, foo2qpdlLogURL] {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let outputHandle = try FileHandle(forWritingTo: output)
        let gsLogHandle = try FileHandle(forWritingTo: gsLogURL)
        let foo2qpdlLogHandle = try FileHandle(forWritingTo: foo2qpdlLogURL)
        defer {
            try? outputHandle.close()
            try? gsLogHandle.close()
            try? foo2qpdlLogHandle.close()
            try? fileManager.removeItem(at: gsLogURL)
            try? fileManager.removeItem(at: foo2qpdlLogURL)
        }
        
        let raster = Pipe()
        
        let ghostscript = Process()
        ghostscript.executableURL = tools.ghostscript
        ghostscript.arguments = ghostscriptArguments(color: color, resolution: resolution) + input
        ghostscript.standardInput = FileHandle.nullDevice
        ghostscript.standardOutput = raster
        ghostscript.standardError = gsLogHandle
        
        let encoder = Process()
        encoder.executableURL = tools.foo2qpdl
        encoder.arguments = foo2qpdlArguments(color: color, resolution: resolution)
        encoder.standardInput = raster
        encoder.standardOutput = outputHandle
        encoder.standardError = foo2qpdlLogHandle
        
        try encoder.run()
        do {
            try ghostscript.run()
        } catch {
            encoder.terminate()
            throw error
        }
        
        ghostscript.waitUntilExit()
        encoder.waitUntilExit()
        
        let gsMessages = Self.readLog(gsLogURL)
        let foo2qpdlMessages = Self.readLog(foo2qpdlLogURL)
        
        guard ghostscript.terminationStatus == 0 else {
            throw QPDLDriverError.ghostscriptFailed(ghostscript.terminationStatus, gsMessages)
        }
        guard encoder.terminationStatus == 0 else {
            throw QPDLDriverError.foo2qpdlFailed(encoder.terminationStatus, foo2qpdlMessages)
        }
        
        let byteCount = (try? fileManager.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
        guard byteCount > 0 else {
            throw QPDLDriverError.emptyOutput
        }
        
        return QPDLPage(
            url: output,
            byteCount: byteCount,
            duration: Date().timeIntervalSince(start),
            messages: [gsMessages, foo2qpdlMessages].filter { !$0.isEmpty }.joined(separator: "\n")
        )
    }
    
    private func ghostscriptArguments(color: Bool, resolution: QPDLResolution) -> [String] {
        let geometry = resolution.geometry
        return [
            "-q", "-dBATCH", "-dSAFER", "-dQUIET", "-dNOPAUSE",
            // Wrapper'daki "|cat 1>&3" hilesinin karşılığı: PS çıktısı rastere karışmasın
            "-sstdout=%stderr",
            "-sPAPERSIZE=a4",
            "-g\(geometry.width)x\(geometry.height)",
            "-r\(resolution.rawValue)",
            "-sDEVICE=\(color ? "bitcmyk" : "pbmraw")",
            "-dCOLORSCREEN", "-dMaxBitmap=500000000",
            // bitcmyk başlıksız: raster boyutu -g ile birebir aynı olmalı.
            // Chromium'un A4'ü (595.92x842.88) ve diğer boyutlar A4'e sığdırılır.
            "-dFIXEDMEDIA", "-dPDFFitPage",
            "-sOutputFile=-",
        ]
    }
    
    private func foo2qpdlArguments(color: Bool, resolution: QPDLResolution) -> [String] {
        let geometry = resolution.geometry
        let clip = "\(geometry.clipX)x\(geometry.clipY)"
        var arguments = [
            "-r\(resolution.rawValue)",
            "-g\(geometry.width)x\(geometry.height)",
            "-p2",  // A4
            "-m0",  // düz kağıt
            "-n1", "-d1", "-s1",
            "-z0",  // CLP-300
        ]
        if color {
            arguments += ["-c", "-B", "-A"]
        }
        arguments += [
            "-u", clip, "-l", clip,
            "-a50,50,50,50,50,50",
            "-J", "", "-U", "",
            "-D0",
        ]
        return arguments
    }
    
    private static func readLog(_ url: URL) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Types

enum QPDLResolution: String, CaseIterable, Identifiable {
    case dpi600 = "600x600"
    case dpi1200x600 = "1200x600"
    case dpi1200 = "1200x1200"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .dpi600: return "600 dpi (hızlı)"
        case .dpi1200x600: return "1200x600 dpi (önerilen)"
        case .dpi1200: return "1200x1200 dpi (en iyi)"
        }
    }
    
    /// A4 raster boyutu ve kenar kırpması (piksel)
    /// Wrapper: XDIM=9920 YDIM=7016 (1200x600), set_clipping 150 100 150 100
    fileprivate var geometry: (width: Int, height: Int, clipX: Int, clipY: Int) {
        switch self {
        case .dpi600: return (4960, 7016, 75, 100)
        case .dpi1200x600: return (9920, 7016, 150, 100)
        case .dpi1200: return (9920, 14032, 150, 100)
        }
    }
}

struct QPDLTools {
    let ghostscript: URL
    let foo2qpdl: URL
}

struct QPDLPage {
    let url: URL
    let byteCount: Int
    let duration: TimeInterval
    /// gs / foo2qpdl stderr (uyarılar dahil)
    let messages: String
}

/// Ayarlar ekranı için: araçlar bulundu mu, sürümleri ne
struct QPDLToolStatus {
    let ghostscript: URL?
    let ghostscriptVersion: String?
    let foo2qpdl: URL?
    let foo2qpdlVersion: String?
    
    var isReady: Bool { ghostscriptVersion != nil && foo2qpdlVersion != nil }
    
    /// "$Id: foo2qpdl.c,v 1.56 2019/09/06 ..." → "1.56"
    var foo2qpdlShortVersion: String? {
        guard let version = foo2qpdlVersion,
              let range = version.range(of: #",v [0-9.]+"#, options: .regularExpression) else {
            return foo2qpdlVersion
        }
        return String(version[range].dropFirst(3))
    }
    
    static func check(ghostscriptPath: String, foo2qpdlPath: String) -> QPDLToolStatus {
        let ghostscript = ToolLocator.ghostscript(customPath: ghostscriptPath)
        let foo2qpdl = ToolLocator.foo2qpdl(customPath: foo2qpdlPath)
        return QPDLToolStatus(
            ghostscript: ghostscript,
            ghostscriptVersion: ghostscript.flatMap { ToolLocator.version(of: $0, argument: "--version") },
            foo2qpdl: foo2qpdl,
            foo2qpdlVersion: foo2qpdl.flatMap { ToolLocator.version(of: $0, argument: "-V") }
        )
    }
}

/// gs ve foo2qpdl'yi bulur: ayardaki yol → uygulama paketi → Homebrew / MacPorts
enum ToolLocator {
    static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
    
    static var bundledFoo2qpdl: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/foo2qpdl")
    }
    
    static func ghostscript(customPath: String) -> URL? {
        find("gs", customPath: customPath, bundled: nil)
    }
    
    static func foo2qpdl(customPath: String) -> URL? {
        find("foo2qpdl", customPath: customPath, bundled: bundledFoo2qpdl)
    }
    
    /// Aracın sürüm satırı (`gs --version`, `foo2qpdl -V`); çalışmazsa nil
    static func version(of tool: URL, argument: String) -> String? {
        let process = Process()
        process.executableURL = tool
        process.arguments = [argument]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return nil }
        let line = String(data: data, encoding: .utf8)?
            .split(separator: "\n").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return line?.isEmpty == false ? line : nil
    }
    
    private static func find(_ name: String, customPath: String, bundled: URL?) -> URL? {
        let fileManager = FileManager.default
        let custom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Elle verilen yol her zaman öncelikli; yanlışsa sessizce başka yere geçme
        if !custom.isEmpty {
            return fileManager.isExecutableFile(atPath: custom) ? URL(fileURLWithPath: custom) : nil
        }
        
        var candidates: [String] = []
        if let bundled = bundled {
            candidates.append(bundled.path)
        }
        candidates += searchDirectories.map { "\($0)/\(name)" }
        
        return candidates
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }
}

// MARK: - Errors
enum QPDLDriverError: LocalizedError {
    case ghostscriptFailed(Int32, String)
    case foo2qpdlFailed(Int32, String)
    case emptyOutput
    
    var errorDescription: String? {
        switch self {
        case .ghostscriptFailed(let status, let messages):
            return "Ghostscript sayfayı çeviremedi (kod \(status)): \(Self.tail(messages))"
        case .foo2qpdlFailed(let status, let messages):
            return "foo2qpdl yazıcı verisini üretemedi (kod \(status)): \(Self.tail(messages))"
        case .emptyOutput:
            return "Yazıcı verisi boş çıktı"
        }
    }
    
    private static func tail(_ text: String) -> String {
        let lines = text.split(separator: "\n").suffix(3).joined(separator: " ")
        return lines.isEmpty ? "ayrıntı yok" : lines
    }
}
