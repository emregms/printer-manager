import Foundation

/// Kendi sürücümüz: bir PDF sayfasını Ghostscript ile rastera çevirir, foo2qpdl ile
/// Samsung CLP-300'ün anladığı QPDL (SPL-C) verisine dönüştürür.
///
/// Parametreler foo2zjs'in `foo2qpdl-wrapper` betiğinin CLP-300 + A4 için ürettiği
/// komutla aynı (`-z0 -p2`, renkte ICM modu: `bitcmyk` + `-c -B -A`).
/// Wrapper'ın yarım ton (WTS) önsözü eklenmiyor: Ghostscript 10'da PDF girdide etkisiz.
///
/// Fotoğraf modu (`tools.colorTables` varsa): gs sürekli tonlu raster (P6/P5) verir,
/// `clp300-raster` Samsung'un renk tablosu ve yarım ton matrisleriyle noktalara çevirir,
/// foo2qpdl `-A -B` olmadan kodlar. gs'nin kendi renk çevrimi ve yarım tonu kullanılmaz.
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
        return try await run(input: input, color: color, tables: tools.colorTables, resolution: resolution, output: output)
    }
    
    /// Çift yön için boş sayfa (kağıt geçer, toner harcanmaz)
    func renderBlankPage(resolution: QPDLResolution, to output: URL) async throws -> QPDLPage {
        return try await run(input: ["-c", "showpage"], color: false, tables: nil, resolution: resolution, output: output)
    }
    
    // MARK: - Private Methods
    
    private func run(
        input: [String],
        color: Bool,
        tables: PrinterColorTables?,
        resolution: QPDLResolution,
        output: URL
    ) async throws -> QPDLPage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let page = try runPipeline(input: input, color: color, tables: tables, resolution: resolution, output: output)
                    continuation.resume(returning: page)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// gs | [clp300-raster |] foo2qpdl > output
    private func runPipeline(
        input: [String],
        color: Bool,
        tables: PrinterColorTables?,
        resolution: QPDLResolution,
        output: URL
    ) throws -> QPDLPage {
        let start = Date()
        let fileManager = FileManager.default
        let photo = tables != nil
        
        // stderr dosyaya: pipe'ta okunmadan dolarsa süreçler kilitlenebilir
        let gsLogURL = output.appendingPathExtension("gs.log")
        let rasterLogURL = output.appendingPathExtension("raster.log")
        let foo2qpdlLogURL = output.appendingPathExtension("foo2qpdl.log")
        for url in [output, gsLogURL, rasterLogURL, foo2qpdlLogURL] {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let outputHandle = try FileHandle(forWritingTo: output)
        let gsLogHandle = try FileHandle(forWritingTo: gsLogURL)
        let rasterLogHandle = try FileHandle(forWritingTo: rasterLogURL)
        let foo2qpdlLogHandle = try FileHandle(forWritingTo: foo2qpdlLogURL)
        defer {
            try? outputHandle.close()
            try? gsLogHandle.close()
            try? rasterLogHandle.close()
            try? foo2qpdlLogHandle.close()
            try? fileManager.removeItem(at: gsLogURL)
            try? fileManager.removeItem(at: rasterLogURL)
            try? fileManager.removeItem(at: foo2qpdlLogURL)
        }
        
        let raster = Pipe()
        
        let ghostscript = Process()
        ghostscript.executableURL = tools.ghostscript
        ghostscript.arguments = ghostscriptArguments(color: color, photo: photo, resolution: resolution) + input
        ghostscript.standardInput = FileHandle.nullDevice
        ghostscript.standardOutput = raster
        ghostscript.standardError = gsLogHandle
        
        let encoder = Process()
        encoder.executableURL = tools.foo2qpdl
        encoder.arguments = foo2qpdlArguments(color: color, photo: photo, resolution: resolution)
        encoder.standardOutput = outputHandle
        encoder.standardError = foo2qpdlLogHandle
        
        // Fotoğraf modu: sürekli tonlu raster Samsung'un tablolarıyla noktalara çevrilir
        var converter: Process?
        if let tables = tables {
            let dots = Pipe()
            let process = Process()
            process.executableURL = tables.helper
            process.arguments = [tables.directory.path, resolution.rawValue]
            process.standardInput = raster
            process.standardOutput = dots
            process.standardError = rasterLogHandle
            encoder.standardInput = dots
            converter = process
        } else {
            encoder.standardInput = raster
        }
        
        try encoder.run()
        do {
            try converter?.run()
            try ghostscript.run()
        } catch {
            converter?.terminate()
            encoder.terminate()
            throw error
        }
        
        ghostscript.waitUntilExit()
        converter?.waitUntilExit()
        encoder.waitUntilExit()
        
        let gsMessages = Self.readLog(gsLogURL)
        let rasterMessages = Self.readLog(rasterLogURL)
        let foo2qpdlMessages = Self.readLog(foo2qpdlLogURL)
        
        guard ghostscript.terminationStatus == 0 else {
            throw QPDLDriverError.ghostscriptFailed(ghostscript.terminationStatus, gsMessages)
        }
        if let converter = converter, converter.terminationStatus != 0 {
            throw QPDLDriverError.rasterFailed(converter.terminationStatus, rasterMessages)
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
            messages: [gsMessages, rasterMessages, foo2qpdlMessages].filter { !$0.isEmpty }.joined(separator: "\n")
        )
    }
    
    private func ghostscriptArguments(color: Bool, photo: Bool, resolution: QPDLResolution) -> [String] {
        let geometry = resolution.geometry
        var arguments = [
            "-q", "-dBATCH", "-dSAFER", "-dQUIET", "-dNOPAUSE",
            // Wrapper'daki "|cat 1>&3" hilesinin karşılığı: PS çıktısı rastere karışmasın
            "-sstdout=%stderr",
            "-sPAPERSIZE=a4",
            "-g\(geometry.width)x\(geometry.height)",
            "-r\(resolution.rawValue)",
        ]
        if photo {
            // Sürekli tonlu: renk çevrimi ve yarım ton clp300-raster'da. MaxBitmap
            // verilmez: gs bantlarla çalışır (1200x1200'de ~420 MB yerine ~30 MB bellek).
            // Küçük görseller sayfaya büyütülürken yumuşatılır, piksel piksel görünmez.
            arguments += ["-sDEVICE=\(color ? "ppmraw" : "pgmraw")", "-dInterpolateControl=-1"]
        } else {
            arguments += ["-sDEVICE=\(color ? "bitcmyk" : "pbmraw")", "-dCOLORSCREEN", "-dMaxBitmap=500000000"]
        }
        arguments += [
            // bitcmyk başlıksız: raster boyutu -g ile birebir aynı olmalı.
            // Chromium'un A4'ü (595.92x842.88) ve diğer boyutlar A4'e sığdırılır.
            "-dFIXEDMEDIA", "-dPDFFitPage",
            "-sOutputFile=-",
        ]
        return arguments
    }
    
    private func foo2qpdlArguments(color: Bool, photo: Bool, resolution: QPDLResolution) -> [String] {
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
            // -A (C+M+Y aynı noktadaysa yalnız siyah) ve -B (siyahın altını boşalt) yazı
            // için; fotoğrafta gölgeleri griye boğar. Samsung'un tablosu siyahı kendisi ayarlar.
            arguments += photo ? ["-c"] : ["-c", "-B", "-A"]
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
    /// Fotoğraf modu için; nil ise gs'nin kendi renk çevrimi kullanılır
    var colorTables: PrinterColorTables?
}

/// Samsung'un Mac sürücüsünün kurduğu CLP-300 renk tablosu (RGB → CMYK) ve yarım ton
/// matrisleri. Fotoğraf modu bunlarla basar. Dosyalar repoda ve uygulamada yoktur;
/// Samsung sürücüsü kuruluysa yerinden okunur (bkz. Driver/clp300-raster.c).
struct PrinterColorTables {
    /// Samsung sürücüsünün kurduğu yer; yoksa kullanıcının koyabileceği klasör (yönetici izni gerekmez)
    static let searchDirectories = [
        URL(fileURLWithPath: "/Library/Printers/Samsung/CLP-300"),
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrinterManager/CLP-300"),
    ]
    static var directory: URL { searchDirectories[0] }
    static var bundledHelper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/clp300-raster")
    }
    
    let directory: URL
    let helper: URL
    
    /// Üç çözünürlüğün dosyalarının hepsi bulunan ilk klasör (yardımcı araç da yerindeyse)
    static func find() -> PrinterColorTables? {
        let fileManager = FileManager.default
        var files = ["RGB2CMYK_6006001", "RGB2CMYK_12006001", "RGB2CMYK_120012001"]
        for color in ["Cyan", "Magenta", "Yellow", "Black", "Gray"] {
            files += ["600", "1200600", "12001200"].map { "\(color)HT_\($0)" }
        }
        guard fileManager.isExecutableFile(atPath: bundledHelper.path),
              let directory = searchDirectories.first(where: { directory in
                  files.allSatisfy { fileManager.isReadableFile(atPath: directory.appendingPathComponent($0).path) }
              }) else {
            return nil
        }
        return PrinterColorTables(directory: directory, helper: bundledHelper)
    }
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
    case rasterFailed(Int32, String)
    case emptyOutput
    
    var errorDescription: String? {
        switch self {
        case .ghostscriptFailed(let status, let messages):
            return "Ghostscript sayfayı çeviremedi (kod \(status)): \(Self.tail(messages))"
        case .foo2qpdlFailed(let status, let messages):
            return "foo2qpdl yazıcı verisini üretemedi (kod \(status)): \(Self.tail(messages))"
        case .rasterFailed(let status, let messages):
            return "Fotoğraf modu renk çevrimi başarısız (kod \(status)): \(Self.tail(messages))"
        case .emptyOutput:
            return "Yazıcı verisi boş çıktı"
        }
    }
    
    private static func tail(_ text: String) -> String {
        let lines = text.split(separator: "\n").suffix(3).joined(separator: " ")
        return lines.isEmpty ? "ayrıntı yok" : lines
    }
}
