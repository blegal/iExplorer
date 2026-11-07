import AppKit
import AVKit
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// Aperçu de l'inspecteur : code coloré, texte, PDF feuilletable, vidéo / audio, image ou Coup d'œil.
/// Chaque type de vue n'est créé qu'au premier besoin, et la lecture s'arrête au changement de sélection.
final class PreviewPane: NSView {
    private enum Kind { case image, text, pdf, media, quickLook }

    let imageView = NSImageView()
    private var textScroll: NSScrollView?
    private var textView: NSTextView?
    private var pdfView: PDFView?
    private var playerView: AVPlayerView?
    private var quickLookView: QLPreviewView?
    private var heightConstraint: NSLayoutConstraint!
    private var generation = 0
    /// Le fichier affiché est rechargé quand il change sur le disque, à la même position.
    private let watcher = FileChangeWatcher()
    /// Fichier montré dans l'aperçu texte.
    private var textURL: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        embed(imageView)
        heightConstraint = heightAnchor.constraint(equalToConstant: 190)
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func embed(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Affiche l'icône ou la miniature (cas par défaut).
    func showImage(_ image: NSImage?) {
        watcher.watch(nil)
        activate(.image)
        imageView.image = image
    }

    /// Choisit l'aperçu adapté au fichier ; `false` si l'image / la miniature suffit.
    @discardableResult
    func show(_ url: URL) -> Bool {
        generation += 1
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) ?? (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else {
            return false
        }
        watcher.watch(nil)
        if type.conforms(to: .pdf) {
            let view = pdfView ?? makePDFView()
            // Même PDF déjà affiché (rafraîchissement du panneau) : on garde la position.
            if !view.isHidden, view.document?.documentURL == url, let document = PDFDocument(url: url) {
                view.replaceDocument(document)
            } else {
                view.document = PDFDocument(url: url)
            }
            activate(.pdf)
            watch(url) { [weak self] in
                if let document = PDFDocument(url: url) { self?.pdfView?.replaceDocument(document) }
            }
            return true
        }
        if type.conforms(to: .audiovisualContent) || type.conforms(to: .audio) {
            let view = playerView ?? makePlayerView()
            view.player = AVPlayer(url: url)
            activate(.media)
            return true
        }
        if SyntaxHighlighter.language(for: url) != nil || type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            // Même fichier déjà affiché (rafraîchissement du panneau) : on garde la position.
            showText(url, type: type, keepPosition: textScroll?.isHidden == false && textURL == url)
            watch(url) { [weak self] in self?.showText(url, type: type, keepPosition: true) }
            return true
        }
        if type.conforms(to: .image) { return false }
        // Documents divers (Office, Keynote, archives…) : Coup d'œil intégré.
        if let view = quickLookView ?? makeQuickLookView() {
            view.previewItem = url as NSURL
            activate(.quickLook)
            watch(url) { [weak self] in self?.quickLookView?.refreshPreviewItem() }
            return true
        }
        return false
    }

    private func watch(_ url: URL, reload: @escaping () -> Void) {
        let current = generation
        watcher.onChange = { [weak self] in
            guard let self, current == self.generation else { return }
            reload()
        }
        watcher.watch(url)
    }

    private func showText(_ url: URL, type: UTType, keepPosition: Bool = false) {
        let (scroll, textView) = textScroll.flatMap { scroll in self.textView.map { (scroll, $0) } } ?? makeTextView()
        let origin = scroll.contentView.bounds.origin
        activate(.text)
        if !keepPosition { textView.string = "" }
        textURL = url
        let current = generation
        let dark = Theme.isDark(effectiveAppearance)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Les 200 premiers Ko suffisent pour un aperçu.
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            let data = (try? handle.read(upToCount: 200_000)) ?? Data()
            try? handle.close()
            let text = String(decoding: data, as: UTF8.self)
            let highlighted = SyntaxHighlighter.highlight(text, language: SyntaxHighlighter.language(for: url), dark: dark)
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                textView.textStorage?.setAttributedString(highlighted)
                if keepPosition { textView.restoreScroll(origin) } else { textView.scroll(.zero) }
            }
        }
    }

    /// Arrête la lecture et libère les documents chargés.
    func reset() {
        generation += 1
        watcher.watch(nil)
        playerView?.player?.pause()
        playerView?.player = nil
        pdfView?.document = nil
        quickLookView?.previewItem = nil
        textView?.string = ""
    }

    private func activate(_ kind: Kind) {
        if kind != .media { playerView?.player?.pause(); playerView?.player = nil }
        if kind != .pdf { pdfView?.document = nil }
        if kind != .quickLook { quickLookView?.previewItem = nil }
        imageView.isHidden = kind != .image
        textScroll?.isHidden = kind != .text
        pdfView?.isHidden = kind != .pdf
        playerView?.isHidden = kind != .media
        quickLookView?.isHidden = kind != .quickLook
        heightConstraint.constant = switch kind {
        case .image: 190
        case .text: 300
        case .pdf, .quickLook: 320
        case .media: 220
        }
    }

    private func makePDFView() -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.backgroundColor = .clear
        embed(view)
        pdfView = view
        return view
    }

    private func makePlayerView() -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        embed(view)
        playerView = view
        return view
    }

    private func makeQuickLookView() -> QLPreviewView? {
        guard let view = QLPreviewView(frame: bounds, style: .compact) else { return nil }
        view.autostarts = true
        embed(view)
        quickLookView = view
        return view
    }

    private func makeTextView() -> (NSScrollView, NSTextView) {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        embed(scroll)
        textScroll = scroll
        self.textView = textView
        return (scroll, textView)
    }
}
