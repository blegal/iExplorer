import Foundation

/// Outils externes facultatifs : détectés dans les dossiers habituels (Homebrew, système) et installables
/// par Homebrew depuis Réglages › Outils externes. Sans eux, les fonctions concernées sont grisées.
enum ExternalTool: String, CaseIterable {
    case sevenZip, rar, unar, bzip3, lzip, brotli, pigz
    case ffmpeg, exiftool, vips, poppler, pandoc
    case ripgrep, fd, fclones
    case age, gnupg
    case rsync
    case latex, typst
    case developerTools

    enum Category: CaseIterable {
        case archives, previews, search, crypto, sync, writing, development

        var title: String {
            switch self {
            case .archives: L("Archives et compression")
            case .previews: L("Aperçus et métadonnées")
            case .search: L("Recherche et doublons")
            case .crypto: L("Chiffrement")
            case .sync: L("Copie et synchronisation")
            case .writing: L("Rédaction")
            case .development: L("Développement")
            }
        }
    }

    var category: Category {
        switch self {
        case .sevenZip, .rar, .unar, .bzip3, .lzip, .brotli, .pigz: .archives
        case .ffmpeg, .exiftool, .vips, .poppler, .pandoc: .previews
        case .ripgrep, .fd, .fclones: .search
        case .age, .gnupg: .crypto
        case .rsync: .sync
        case .latex, .typst: .writing
        case .developerTools: .development
        }
    }

    var title: String {
        switch self {
        case .sevenZip: "7-Zip"
        case .rar: "RAR"
        case .unar: "The Unarchiver (unar)"
        case .bzip3: "bzip3"
        case .lzip: "lzip"
        case .brotli: "Brotli"
        case .pigz: "pigz"
        case .ffmpeg: "FFmpeg"
        case .exiftool: "ExifTool"
        case .vips: "libvips"
        case .poppler: "Poppler"
        case .pandoc: "Pandoc"
        case .ripgrep: "ripgrep"
        case .fd: "fd"
        case .fclones: "fclones"
        case .age: "age"
        case .gnupg: "GnuPG"
        case .rsync: "rsync 3"
        case .latex: "LaTeX (BasicTeX)"
        case .typst: "Typst"
        case .developerTools: L("Outils de développement Apple")
        }
    }

    var purpose: String {
        switch self {
        case .sevenZip: L("7z chiffré aux noms masqués, archives rar et 7z protégées par mot de passe")
        case .rar: L("Création d’archives .rar (logiciel RARLAB, licence shareware)")
        case .unar: L("Lecture de formats anciens ou rares (sit, lha, arj, rar5…)")
        case .bzip3: L("Archives .tar.bz3 (meilleur taux que bzip2 sur le texte et le code)")
        case .lzip: L("Archives .tar.lz (format d’archivage à long terme)")
        case .brotli: L("Archives .tar.br")
        case .pigz: L("gzip sur tous les cœurs du processeur (tar.gz bien plus rapide)")
        case .ffmpeg: L("Vidéos et sons hors QuickLook (mkv, webm, flac…) : miniatures, durée, codecs")
        case .exiftool: L("Métadonnées complètes des photos (RAW, XMP, IPTC, GPS) et des documents")
        case .vips: L("Miniatures rapides des grandes images (RAW, WebP, AVIF, TIFF géants)")
        case .poppler: L("Texte des PDF (pdftotext) pour la recherche dans le contenu")
        case .pandoc: L("Aperçu des documents docx, odt, epub, LaTeX convertis en HTML")
        case .ripgrep: L("Recherche ultra-rapide dans le contenu des fichiers, même hors index Spotlight")
        case .fd: L("Recherche rapide par nom dans les sous-dossiers")
        case .fclones: L("Recherche des fichiers en double")
        case .age: L("Chiffrement moderne de fichiers (.age), lisible sur Linux et Windows")
        case .gnupg: L("Fichiers .gpg et .asc : chiffrement, déchiffrement, signatures")
        case .rsync: L("Synchronisation plus rapide et plus complète que l’rsync de macOS")
        case .latex: L("Compilation des .tex dans l’éditeur, avec l’aperçu PDF à côté")
        case .typst: L("Compilation des .typ dans l’éditeur, avec l’aperçu PDF à côté")
        case .developerTools: L("git : état Git des fichiers, commit et push depuis l’éditeur")
        }
    }

    /// Exécutables cherchés, par ordre de préférence.
    var binaries: [String] {
        switch self {
        case .sevenZip: ["7zz", "7z"]
        case .rar: ["rar"]
        case .unar: ["unar"]
        case .bzip3: ["bzip3"]
        case .lzip: ["lzip"]
        case .brotli: ["brotli"]
        case .pigz: ["pigz"]
        case .ffmpeg: ["ffprobe"]
        case .exiftool: ["exiftool"]
        case .vips: ["vips"]
        case .poppler: ["pdftotext"]
        case .pandoc: ["pandoc"]
        case .ripgrep: ["rg"]
        case .fd: ["fd"]
        case .fclones: ["fclones"]
        case .age: ["age"]
        case .gnupg: ["gpg"]
        case .rsync: ["rsync"]
        case .latex: ["latexmk", "pdflatex"]
        case .typst: ["typst"]
        case .developerTools: ["git"]
        }
    }

    /// Paquet Homebrew (`nil` : installé autrement).
    var brewPackage: (name: String, cask: Bool)? {
        switch self {
        case .sevenZip: ("sevenzip", false)
        case .rar: ("rar", true)
        case .unar: ("unar", false)
        case .bzip3: ("bzip3", false)
        case .lzip: ("lzip", false)
        case .brotli: ("brotli", false)
        case .pigz: ("pigz", false)
        case .ffmpeg: ("ffmpeg", false)
        case .exiftool: ("exiftool", false)
        case .vips: ("vips", false)
        case .poppler: ("poppler", false)
        case .pandoc: ("pandoc", false)
        case .ripgrep: ("ripgrep", false)
        case .fd: ("fd", false)
        case .fclones: ("fclones", false)
        case .age: ("age", false)
        case .gnupg: ("gnupg", false)
        case .rsync: ("rsync", false)
        case .latex: ("basictex", true)
        case .typst: ("typst", false)
        case .developerTools: nil
        }
    }

    /// rsync existe déjà dans macOS (ancienne version) : seule celle de Homebrew compte.
    private var searchPaths: [String] {
        switch self {
        case .rsync: ["/opt/homebrew/bin", "/usr/local/bin"]
        case .latex: ["/Library/TeX/texbin"] + Self.searchPaths
        default: Self.searchPaths
        }
    }

    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    var path: URL? {
        if self == .developerTools {
            // /usr/bin/git n'est qu'un relais tant que les outils de développement ne sont pas installés.
            return GitService.shared.isAvailable ? URL(fileURLWithPath: "/usr/bin/git") : nil
        }
        for binary in binaries {
            for directory in searchPaths {
                let candidate = directory + "/" + binary
                if FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
            }
        }
        return nil
    }

    var isInstalled: Bool { path != nil }

    /// Outil déjà utilisé par une fonction d'iExplorer (les autres sont signalés « intégration à venir »).
    var isUsed: Bool {
        switch self {
        case .sevenZip, .rar, .unar, .bzip3, .lzip, .brotli, .pigz, .latex, .typst, .developerTools: true
        default: false
        }
    }

    static var homebrew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Bibliothèques compilées dans l'app ou fournies par macOS (affichées pour information).
    static let builtIn: [(title: String, purpose: String)] = [
        (L("libarchive (bsdtar de macOS)"), L("zip (AES-256), 7z, tar.gz, tar.bz2, tar.xz ; lecture de rar, iso, cab…")),
        (L("zstd 1.5.7 (intégré)"), L("Archives .tar.zst")),
        (L("LZ4 1.10.0 (intégré)"), L("Archives .tar.lz4")),
        ("CryptoKit (macOS)", L("Chiffrement AES-256-GCM et ChaCha20-Poly1305, sommes SHA")),
    ]
}

/// Compression en flux par un outil externe (tar | outil > archive) : bzip3, lzip, Brotli.
enum ExternalCodec {
    /// pigz ne sert qu'à créer les tar.gz (la lecture reste au tar du système).
    case bzip3, lzip, brotli, pigz

    init?(archive: URL) {
        let name = archive.lastPathComponent.lowercased()
        if name.hasSuffix(".bz3") { self = .bzip3 }
        else if name.hasSuffix(".lz") { self = .lzip }
        else if name.hasSuffix(".br") { self = .brotli }
        else { return nil }
    }

    var tool: ExternalTool {
        switch self {
        case .bzip3: .bzip3
        case .lzip: .lzip
        case .brotli: .brotli
        case .pigz: .pigz
        }
    }

    /// Arguments pour compresser l'entrée standard vers la sortie standard.
    func compressArguments(level: Int) -> [String] {
        switch self {
        case .bzip3: ["-e", "-c", "-b", "\(level)"]
        case .lzip: ["-c", "-\(level)"]
        case .brotli: ["-c", "-q", "\(level)"]
        case .pigz: ["-c", "-\(level)"]
        }
    }

    var decompressArguments: [String] { ["-d", "-c"] }

    /// Deux processus reliés : sans cela, chacun hériterait des extrémités des tubes de l'autre
    /// et la fin de flux n'arriverait jamais (blocage).
    private static func closeOnExec(_ pipes: Pipe...) {
        for pipe in pipes {
            for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
            }
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// tar → (lu ici, pour la progression) → outil → archive.
    func createTar(_ names: [String], in directory: URL, to target: URL, level: Int, exclude: [String], job: FileJob) throws {
        guard let toolPath = tool.path else { throw Failure(message: L("\(tool.title) n’est pas installé (Réglages › Outils externes).")) }
        let tar = Process(), compressor = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-c", "--no-mac-metadata"] + exclude.flatMap { ["--exclude", $0] } + ["-f", "-", "-C", directory.path, "--"] + names
        compressor.executableURL = toolPath
        compressor.arguments = compressArguments(level: level)
        // Un tube par processus : Foundation ferme le côté enfant d'un tube dès le premier lancement.
        let fromTar = Pipe(), toTool = Pipe(), tarErrors = Pipe(), toolErrors = Pipe()
        Self.closeOnExec(fromTar, toTool, tarErrors, toolErrors)
        tar.standardOutput = fromTar
        tar.standardError = tarErrors
        tar.standardInput = FileHandle.nullDevice
        compressor.standardInput = toTool
        compressor.standardError = toolErrors
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        compressor.standardOutput = output
        job.setCancelAction { tar.terminate(); compressor.terminate() }
        try compressor.run()
        try tar.run()
        var done: Int64 = 0
        var failure: Error?
        do {
            while let data = try fromTar.fileHandleForReading.read(upToCount: 1 << 20), !data.isEmpty {
                job.waitIfPaused()
                if job.isCancelled { throw CancellationError() }
                try toTool.fileHandleForWriting.write(contentsOf: data)
                done += Int64(data.count)
                job.setDone(done)
            }
        } catch {
            failure = error
            tar.terminate()
        }
        try? toTool.fileHandleForWriting.close()
        tar.waitUntilExit()
        compressor.waitUntilExit()
        if let failure { throw failure }
        if tar.terminationStatus != 0 || compressor.terminationStatus != 0 {
            let message = String(decoding: (tar.terminationStatus != 0 ? tarErrors : toolErrors).fileHandleForReading.availableData, as: UTF8.self)
            throw Failure(message: message.isEmpty ? L("\(tool.title) a échoué.") : message)
        }
    }

    /// archive → (lu ici) → outil → tar -x.
    func extractTar(_ archive: URL, into folder: URL, extraArguments: [String] = [], job: FileJob?) throws {
        guard let toolPath = tool.path else { throw Failure(message: L("\(tool.title) n’est pas installé (Réglages › Outils externes).")) }
        let decompressor = Process(), tar = Process()
        decompressor.executableURL = toolPath
        decompressor.arguments = decompressArguments
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-x", "-f", "-", "-C", folder.path] + extraArguments
        let toTool = Pipe(), between = Pipe(), toolErrors = Pipe(), tarErrors = Pipe()
        Self.closeOnExec(toTool, between, toolErrors, tarErrors)
        decompressor.standardInput = toTool
        decompressor.standardOutput = between
        decompressor.standardError = toolErrors
        tar.standardInput = between
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = tarErrors
        job?.setCancelAction { decompressor.terminate(); tar.terminate() }
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        try tar.run()
        try decompressor.run()
        var done: Int64 = 0
        var failure: Error?
        do {
            while let data = try input.read(upToCount: 1 << 20), !data.isEmpty {
                job?.waitIfPaused()
                if job?.isCancelled == true { throw CancellationError() }
                try toTool.fileHandleForWriting.write(contentsOf: data)
                done += Int64(data.count)
                job?.setDone(done)
            }
        } catch {
            failure = error
            decompressor.terminate()
        }
        try? toTool.fileHandleForWriting.close()
        decompressor.waitUntilExit()
        tar.waitUntilExit()
        if let failure { throw failure }
        if decompressor.terminationStatus != 0 || tar.terminationStatus != 0 {
            let message = String(decoding: (tar.terminationStatus != 0 ? tarErrors : toolErrors).fileHandleForReading.availableData, as: UTF8.self)
            throw Failure(message: message.isEmpty ? L("\(tool.title) a échoué.") : message)
        }
    }

    /// Fichier seul compressé (.bz3, .lz, .br sans tar) : restitué tel quel.
    func decompressFile(_ archive: URL, to target: URL) throws {
        guard let toolPath = tool.path else { throw Failure(message: L("\(tool.title) n’est pas installé (Réglages › Outils externes).")) }
        let process = Process()
        process.executableURL = toolPath
        process.arguments = decompressArguments
        process.standardInput = try FileHandle(forReadingFrom: archive)
        FileManager.default.createFile(atPath: target.path, contents: nil)
        process.standardOutput = try FileHandle(forWritingTo: target)
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw Failure(message: L("\(tool.title) a échoué.")) }
    }
}
