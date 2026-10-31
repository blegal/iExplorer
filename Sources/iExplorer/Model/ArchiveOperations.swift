import AppKit

enum ArchiveFormat: Int, CaseIterable {
    case zip, tarGz, tarBz2, tarXz, tarZst, tarLz4, sevenZ, rar, tarBz3, tarLz, tarBr

    /// Ordre des menus : archives courantes, puis la famille tar.
    static let menuOrder: [ArchiveFormat] = [.zip, .sevenZ, .rar, .tarGz, .tarBz2, .tarXz, .tarZst, .tarLz4, .tarBz3, .tarLz, .tarBr]

    /// Outil externe nécessaire pour créer ce format (`nil` : macOS ou l'app suffisent).
    var requiredTool: ExternalTool? {
        switch self {
        case .rar: .rar
        case .tarBz3: .bzip3
        case .tarLz: .lzip
        case .tarBr: .brotli
        default: nil
        }
    }

    var isAvailable: Bool { requiredTool?.isInstalled ?? true }

    var externalCodec: ExternalCodec? {
        switch self {
        case .tarBz3: .bzip3
        case .tarLz: .lzip
        case .tarBr: .brotli
        default: nil
        }
    }

    var fileExtension: String {
        switch self {
        case .zip: "zip"
        case .tarGz: "tar.gz"
        case .tarBz2: "tar.bz2"
        case .tarXz: "tar.xz"
        case .tarZst: "tar.zst"
        case .tarLz4: "tar.lz4"
        case .sevenZ: "7z"
        case .rar: "rar"
        case .tarBz3: "tar.bz3"
        case .tarLz: "tar.lz"
        case .tarBr: "tar.br"
        }
    }

    /// zstd et LZ4 sont embarqués : le tar du système ne les connaît pas.
    var codec: StreamCodec? {
        switch self {
        case .tarZst: .zstd
        case .tarLz4: .lz4
        default: nil
        }
    }

    /// zip, 7z et rar savent chiffrer (AES-256).
    var supportsPassword: Bool { self == .zip || self == .sevenZ || self == .rar }

    /// Nom du filtre pour l'option « compression-level » du tar du système.
    fileprivate var libarchiveOption: String? {
        switch self {
        case .zip: "zip"
        case .tarGz: "gzip"
        case .tarBz2: "bzip2"
        case .tarXz: "xz"
        case .sevenZ: "7zip"
        case .tarZst, .tarLz4, .rar, .tarBz3, .tarLz, .tarBr: nil
        }
    }

    /// Niveau réel de l'outil pour Légère / Normale / Forte.
    func level(_ level: CompressionLevel) -> Int {
        switch (self, level) {
        case (.tarZst, .light): 3
        case (.tarZst, .normal): 6
        case (.tarZst, .strong): 19
        case (.tarLz4, .light): 0
        case (.tarLz4, .normal): 3
        case (.tarLz4, .strong): 12
        case (.rar, .light): 1
        case (.rar, .normal): 3
        case (.rar, .strong): 5
        case (.tarBz3, .light): 1
        case (.tarBz3, .normal): 16
        case (.tarBz3, .strong): 256
        case (.tarBr, .light): 4
        case (.tarBr, .normal): 7
        case (.tarBr, .strong): 11
        case (_, .light): 1
        case (_, .normal): 6
        case (_, .strong): 9
        }
    }

    func levelDescription(_ level: CompressionLevel) -> String {
        switch self {
        case .tarZst: "zstd niveau \(self.level(level))"
        case .tarLz4: level == .light ? "LZ4 rapide" : "LZ4 HC niveau \(self.level(level))"
        case .rar: "rar -m\(self.level(level))"
        case .tarBz3: "blocs de \(self.level(level)) Mo"
        case .tarBr: "Brotli qualité \(self.level(level))"
        default: "niveau \(self.level(level))"
        }
    }

    /// Dernier niveau choisi pour ce format (coché dans le menu).
    var lastLevel: CompressionLevel {
        get { CompressionLevel(rawValue: UserDefaults.standard.integer(forKey: "compressionLevel.\(fileExtension)") - 1) ?? .normal }
        nonmutating set { UserDefaults.standard.set(newValue.rawValue + 1, forKey: "compressionLevel.\(fileExtension)") }
    }

    /// Format de ⌥⌘K (le dernier utilisé).
    static var lastUsed: ArchiveFormat {
        get { ArchiveFormat(rawValue: UserDefaults.standard.integer(forKey: "compressionFormat")) ?? .zip }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "compressionFormat") }
    }
}

enum CompressionLevel: Int, CaseIterable {
    case light, normal, strong

    var title: String {
        switch self {
        case .light: "Légère"
        case .normal: "Normale"
        case .strong: "Forte"
        }
    }
}

/// Une compression à faire : quoi, en quel format, à quel niveau, où et sous quel nom.
struct CompressionRequest {
    var urls: [URL]
    var format: ArchiveFormat
    var level: CompressionLevel
    /// Nom sans extension.
    var name: String
    var destination: URL
    var password: String?
    /// 7z chiffré : noms des fichiers masqués.
    var hideNames = true
    /// Sans .DS_Store ni fichiers « ._ » de macOS.
    var excludeSystemFiles = true

    /// Nom proposé : celui de l'élément, ou du dossier quand il y en a plusieurs.
    static func defaultName(for urls: [URL]) -> String {
        guard let first = urls.first else { return "Archive" }
        return urls.count == 1 ? first.lastPathComponent : first.deletingLastPathComponent().lastPathComponent
    }
}

/// Compression et décompression avec les outils du système (bsdtar / libarchive, gzip, bzip2).
extension FileOperationCenter {
    private static let archiveSuffixes = ["zip", "tar", "tgz", "tbz", "tbz2", "txz", "tar.gz", "tar.bz2", "tar.xz", "tar.zst",
                                          "gz", "bz2", "xz", "tzst", "tar.lz4", "zst", "lz4", "tar.bz3", "bz3", "tar.lz", "lz", "tar.br", "br", "7z", "rar", "cpio", "xar", "iso", "jar", "cab", "lha", "lzh"]

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return archiveSuffixes.contains { name.hasSuffix("." + $0) }
    }

    /// Compresse selon la demande (format, niveau, nom, destination, mot de passe éventuel).
    func compress(_ request: CompressionRequest, undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        guard let first = request.urls.first else { return }
        let source = first.deletingLastPathComponent()
        let names = request.urls.map(\.lastPathComponent)
        let format = request.format
        let target = uniqueURL(for: request.destination.appendingPathComponent("\(request.name).\(format.fileExtension)"), suffix: "")
        let what = request.urls.count == 1 ? first.lastPathComponent : "\(request.urls.count) éléments"
        let title = (request.password == nil ? "Compression" : "Compression chiffrée") + " de « \(what) »"
        let level = format.level(request.level)
        format.lastLevel = request.level
        ArchiveFormat.lastUsed = format
        let systemFiles = [".DS_Store", "._*", "__MACOSX"]

        if let codec = format.codec {
            compressStreamed(names, in: source, codec: codec, level: level, exclude: request.excludeSystemFiles ? systemFiles : [],
                             target: target, total: request.urls.reduce(Int64(0)) { $0 + Self.allocatedSize(of: $1) },
                             title: title, undoManager: undoManager, completion: completion)
            return
        }
        if let tool = format.requiredTool, !tool.isInstalled {
            showError("Le format .\(format.fileExtension) demande \(tool.title) : installez-le dans Réglages › Outils externes.")
            return
        }
        if let codec = format.externalCodec {
            compressExternal(names, in: source, codec: codec, level: level, exclude: request.excludeSystemFiles ? systemFiles : [],
                             target: target, total: request.urls.reduce(Int64(0)) { $0 + Self.allocatedSize(of: $1) },
                             title: title, undoManager: undoManager, completion: completion)
            return
        }
        if format == .rar, let tool = ExternalTool.rar.path {
            // -ep1 : chemins relatifs aux éléments ; -hp : données et noms chiffrés.
            var arguments = ["a", "-idq", "-y", "-r", "-ep1", "-m\(level)"] + (request.password.map { ["-hp" + $0] } ?? [])
            if request.excludeSystemFiles { arguments += ["-x*.DS_Store", "-x*/._*", "-x*/__MACOSX"] }
            runArchiveTool(tool.path, arguments + ["--", target.path] + names, title: title, output: target, currentDirectory: source,
                           undoManager: undoManager, completion: completion)
            return
        }
        if format == .sevenZ, let password = request.password {
            guard let tool = Self.sevenZip else { showError("Le 7z chiffré demande 7-Zip (brew install sevenzip)."); return }
            var arguments = ["a", "-t7z", "-y", "-mx=\(level)", "-p" + password] + (request.hideNames ? ["-mhe=on"] : [])
            if request.excludeSystemFiles { arguments += systemFiles.map { "-xr!" + $0 } }
            runArchiveTool(tool.path, arguments + ["--", target.path] + names, title: title, output: target, currentDirectory: source,
                           undoManager: undoManager, completion: completion)
            return
        }
        var options = format.libarchiveOption.map { ["\($0):compression-level=\(level)"] } ?? []
        var arguments = ["-a", "-c", "--no-mac-metadata"]
        if let password = request.password, format == .zip {
            options.append("zip:encryption=aes256")
            arguments += ["--passphrase", password]
        }
        if !options.isEmpty { arguments += ["--options", options.joined(separator: ",")] }
        if request.excludeSystemFiles { arguments += systemFiles.flatMap { ["--exclude", $0] } }
        arguments += ["-f", target.path, "-C", source.path, "--"] + names
        runArchiveTool("/usr/bin/tar", arguments, title: title, output: target, undoManager: undoManager, completion: completion)
    }

    // MARK: zstd et LZ4 (embarqués)

    private func compressStreamed(_ names: [String], in directory: URL, codec: StreamCodec, level: Int, exclude: [String], target: URL,
                                  total: Int64, title: String, undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        let job = FileJob(title: title)
        job.setStatus(target.lastPathComponent)
        job.setTotal(total)
        addJob(job)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                job.waitIfPaused()
                try codec.createTar(names, in: directory, to: target, level: level, exclude: exclude, job: job)
            } catch is CancellationError {
            } catch {
                if !job.isCancelled { failure = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self.removeJob(job)
                guard failure == nil, !job.isCancelled else {
                    try? FileManager.default.removeItem(at: target)
                    if let failure { self.showError("\(title) a échoué.\n\(failure)") }
                    completion(nil)
                    return
                }
                undoManager?.registerUndo(withTarget: self) { $0.trash([target], undoManager: undoManager, actionName: "Archive") }
                undoManager?.setActionName("Compression")
                completion(target)
            }
        }
    }

    private func extractStreamed(_ archive: URL, codec: StreamCodec, base: String, into directory: URL, title: String,
                                 undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        let name = archive.lastPathComponent.lowercased()
        // Un fichier seul compressé (.zst, .lz4 sans tar) est restitué tel quel.
        let isTar = name.contains(".tar.") || name.hasSuffix(".tzst")
        let target = uniqueURL(for: directory.appendingPathComponent(base), suffix: "")
        do {
            if isTar { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
            else { FileManager.default.createFile(atPath: target.path, contents: nil) }
        } catch {
            showError(error.localizedDescription)
            return
        }
        let job = FileJob(title: title)
        job.setStatus(archive.lastPathComponent)
        job.setTotal(Int64((try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        addJob(job)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                job.waitIfPaused()
                if isTar {
                    try codec.extractTar(archive, into: target, job: job)
                } else {
                    let input = try FileHandle(forReadingFrom: archive), output = try FileHandle(forWritingTo: target)
                    defer { try? input.close(); try? output.close() }
                    try codec.decompress(from: input, to: output, progress: { job.waitIfPaused(); job.setDone($0) }, isCancelled: { job.isCancelled })
                }
            } catch is CancellationError {
            } catch {
                if !job.isCancelled { failure = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self.removeJob(job)
                guard failure == nil, !job.isCancelled else {
                    try? FileManager.default.removeItem(at: target)
                    if let failure { self.showError("\(title) a échoué.\n\(failure)") }
                    completion(nil)
                    return
                }
                let result = isTar ? self.flattenSingleItem(target) : target
                undoManager?.registerUndo(withTarget: self) { $0.trash([result], undoManager: undoManager, actionName: "Décompression") }
                undoManager?.setActionName("Décompression")
                completion(result)
            }
        }
    }

    // MARK: bzip3, lzip, Brotli (outils externes)

    private func compressExternal(_ names: [String], in directory: URL, codec: ExternalCodec, level: Int, exclude: [String], target: URL,
                                  total: Int64, title: String, undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        runPipelineJob(title: title, status: target.lastPathComponent, total: total, output: target, undoManager: undoManager,
                       actionName: "Compression", completion: completion) { job in
            try codec.createTar(names, in: directory, to: target, level: level, exclude: exclude, job: job)
            return target
        }
    }

    private func extractExternal(_ archive: URL, codec: ExternalCodec, base: String, into directory: URL, title: String,
                                 undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        let name = archive.lastPathComponent.lowercased()
        let isTar = name.contains(".tar.")
        let target = uniqueURL(for: directory.appendingPathComponent(base), suffix: "")
        if isTar {
            do { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) } catch {
                showError(error.localizedDescription)
                return
            }
        }
        let total = Int64((try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        runPipelineJob(title: title, status: archive.lastPathComponent, total: total, output: target, undoManager: undoManager,
                       actionName: "Décompression", completion: completion) { [weak self] job in
            if isTar {
                try codec.extractTar(archive, into: target, job: job)
                return self?.flattenSingleItem(target) ?? target
            }
            try codec.decompressFile(archive, to: target)
            return target
        }
    }

    /// Opération en arrière-plan dans la liste des opérations ; l'élément produit est retiré en cas d'échec.
    private func runPipelineJob(title: String, status: String, total: Int64, output: URL, undoManager: UndoManager?, actionName: String,
                                completion: @escaping (URL?) -> Void, work: @escaping (FileJob) throws -> URL) {
        let job = FileJob(title: title)
        job.setStatus(status)
        job.setTotal(total)
        addJob(job)
        DispatchQueue.global(qos: .userInitiated).async {
            var result: URL?
            var failure: String?
            do {
                job.waitIfPaused()
                result = try work(job)
            } catch is CancellationError {
            } catch {
                if !job.isCancelled { failure = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self.removeJob(job)
                guard let result, failure == nil, !job.isCancelled else {
                    try? FileManager.default.removeItem(at: output)
                    if let failure { self.showError("\(title) a échoué.\n\(failure)") }
                    completion(nil)
                    return
                }
                undoManager?.registerUndo(withTarget: self) { $0.trash([result], undoManager: undoManager, actionName: actionName) }
                undoManager?.setActionName(actionName)
                completion(result)
            }
        }
    }

    /// Taille d'un fichier ou d'un dossier (progression approximative de la compression).
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard (try? url.resourceValues(forKeys: keys))?.isDirectory == true else {
            return Int64((try? url.resourceValues(forKeys: keys))?.fileSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let item = enumerator?.nextObject() as? URL { total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        return total
    }

    // MARK: Archives chiffrées

    /// 7-Zip installé (Homebrew ou autre) : 7z chiffré, noms masqués, rar chiffrés. Sinon zip AES-256 du système seulement.
    static var sevenZip: URL? { ExternalTool.sevenZip.path }

    /// Demande le mot de passe d'une archive ; `nil` si l'utilisateur renonce.
    static func askPassword(for archive: URL, retry: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = retry ? "Mot de passe incorrect" : "« \(archive.lastPathComponent) » est protégée par un mot de passe"
        alert.informativeText = "Saisissez le mot de passe de l’archive."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Décompresser")
        alert.addButton(withTitle: "Annuler")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    private static func needsPassword(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["passphrase", "password", "encrypt"].contains { lower.contains($0) }
    }

    /// Décompresse une archive dans un nouveau dossier nommé d'après elle, dans `directory`.
    func extract(_ archive: URL, into directory: URL, undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        let lower = archive.lastPathComponent.lowercased()
        var base = archive.lastPathComponent
        for suffix in Self.archiveSuffixes.sorted(by: { $0.count > $1.count }) where lower.hasSuffix("." + suffix) {
            base = String(base.dropLast(suffix.count + 1))
            break
        }
        let title = "Décompression de « \(archive.lastPathComponent) »"
        if let codec = StreamCodec(archive: archive) {
            extractStreamed(archive, codec: codec, base: base, into: directory, title: title, undoManager: undoManager, completion: completion)
            return
        }
        if let codec = ExternalCodec(archive: archive) {
            extractExternal(archive, codec: codec, base: base, into: directory, title: title, undoManager: undoManager, completion: completion)
            return
        }
        let isTar = lower.contains(".tar.") || ["tgz", "tbz", "tbz2", "txz"].contains(archive.pathExtension.lowercased())
        // Fichier unique compressé (.gz / .bz2 sans tar) : on restitue le fichier.
        if !isTar, let tool = ["gz": "/usr/bin/gzip", "bz2": "/usr/bin/bzip2"][archive.pathExtension.lowercased()] {
            let target = uniqueURL(for: directory.appendingPathComponent(base), suffix: "")
            runArchiveTool(tool, ["-d", "-c", archive.path], title: title, output: target, stdoutTo: target,
                           undoManager: undoManager, completion: completion)
            return
        }
        extractFolder(archive, base: base, into: directory, title: title, password: nil, undoManager: undoManager, completion: completion)
    }

    /// Décompression dans un dossier ; une archive chiffrée fait demander le mot de passe, puis réessayer.
    private func extractFolder(_ archive: URL, base: String, into directory: URL, title: String, password: String?,
                               undoManager: UndoManager?, completion: @escaping (URL?) -> Void) {
        let target = uniqueURL(for: directory.appendingPathComponent(base), suffix: "")
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch {
            showError(error.localizedDescription)
            return
        }
        let ext = archive.pathExtension.lowercased()
        let tool: String, arguments: [String]
        if let password, ["7z", "rar"].contains(ext) || ext == "zip" && Self.sevenZip != nil, let sevenZip = Self.sevenZip {
            tool = sevenZip.path
            arguments = ["x", "-y", "-p" + password, "-o" + target.path, "--", archive.path]
        } else {
            tool = "/usr/bin/tar"
            arguments = (password.map { ["--passphrase", $0] } ?? []) + ["-x", "-f", archive.path, "-C", target.path]
        }
        runArchiveTool(tool, arguments, title: title, output: target, undoManager: nil, onPasswordNeeded: { [weak self] in
            guard let self, let password = Self.askPassword(for: archive, retry: password != nil) else { completion(nil); return }
            extractFolder(archive, base: base, into: directory, title: title, password: password, undoManager: undoManager, completion: completion)
        }) { [weak self] folder in
            guard let self, let folder else { completion(nil); return }
            let result = flattenSingleItem(folder)
            undoManager?.registerUndo(withTarget: self) { $0.trash([result], undoManager: undoManager, actionName: "Décompression") }
            undoManager?.setActionName("Décompression")
            completion(result)
        }
    }

    /// Évite « Dossier/Dossier/… » quand l'archive ne contient qu'un élément au premier niveau.
    private func flattenSingleItem(_ folder: URL) -> URL {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              children.count == 1, let only = children.first else { return folder }
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".efm-extract-\(UUID().uuidString)")
        do {
            try fm.moveItem(at: only, to: staging)
            try fm.removeItem(at: folder)
            let target = uniqueURL(for: folder.deletingLastPathComponent().appendingPathComponent(only.lastPathComponent), suffix: "")
            try fm.moveItem(at: staging, to: target)
            return target
        } catch {
            return fm.fileExists(atPath: folder.path) ? folder : staging
        }
    }

    /// `onPasswordNeeded` : appelé (sans message d'erreur) quand l'outil réclame un mot de passe.
    private func runArchiveTool(_ tool: String, _ arguments: [String], title: String, output: URL, stdoutTo: URL? = nil,
                                currentDirectory: URL? = nil, undoManager: UndoManager?, onPasswordNeeded: (() -> Void)? = nil,
                                completion: @escaping (URL?) -> Void) {
        let job = FileJob(title: title)
        job.setStatus(output.lastPathComponent)
        addJob(job)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        // Jamais de saisie au clavier : sans terminal, un outil qui attend un mot de passe échoue aussitôt.
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        if let stdoutTo {
            FileManager.default.createFile(atPath: stdoutTo.path, contents: nil)
            process.standardOutput = try? FileHandle(forWritingTo: stdoutTo)
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        job.setCancelAction { process.terminate() }

        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                job.waitIfPaused() // attend son tour en mode « à la suite »
                if job.isCancelled { throw CancellationError() }
                try process.run()
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus != 0 && !job.isCancelled {
                    failure = message.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.removeJob(job)
                if job.isCancelled || failure != nil {
                    try? FileManager.default.removeItem(at: output)
                    if let failure, let onPasswordNeeded, Self.needsPassword(failure) {
                        onPasswordNeeded()
                        return
                    }
                    if let failure { self.showError("\(title) a échoué.\n\(String(failure.suffix(600)))") }
                    completion(nil)
                    return
                }
                undoManager?.registerUndo(withTarget: self) { $0.trash([output], undoManager: undoManager, actionName: "Archive") }
                undoManager?.setActionName(title.components(separatedBy: " ").first ?? "Archive")
                completion(output)
            }
        }
    }
}
