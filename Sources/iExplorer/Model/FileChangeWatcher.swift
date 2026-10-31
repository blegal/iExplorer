import Foundation

/// Surveille un fichier affiché : `onChange` quand sa date ou sa taille change, une fois l'écriture terminée
/// (deux relevés identiques de suite). Un simple relevé périodique suit aussi bien les écritures sur place
/// (pdflatex) que les remplacements atomiques (éditeurs, git).
final class FileChangeWatcher {
    var onChange: (() -> Void)?

    private struct Signature: Equatable {
        let date: Date?
        let size: Int?
    }

    private(set) var url: URL?
    private var seen: Signature?
    private var pending: Signature?
    private var timer: Timer?

    /// Commence à surveiller `url` (ou arrête avec `nil`) ; l'état actuel du fichier sert de référence.
    func watch(_ url: URL?) {
        timer?.invalidate()
        timer = nil
        self.url = url
        pending = nil
        guard let url, url.isFileURL else { return }
        seen = Self.signature(of: url)
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    private func check() {
        guard let url else { return }
        let now = Self.signature(of: url)
        guard now != seen, now.date != nil else { pending = nil; return }
        if now == pending {
            seen = now
            pending = nil
            onChange?()
        } else {
            pending = now
        }
    }

    private static func signature(of url: URL) -> Signature {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return Signature(date: values?.contentModificationDate, size: values?.fileSize)
    }
}
