import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Galerie (⌘6) : la grille d'icônes en mosaïque, chaque vignette à la proportion de son image,
/// en colonnes de même largeur remplies par la plus courte (façon Pinterest).
extension PanelViewController {
    /// Largeur visée d'une colonne : suit le zoom des icônes (80 pt d'icône → colonnes de 200 pt).
    var galleryColumnWidth: CGFloat { iconSize * 2.5 }

    /// Met la grille en mosaïque ou en icônes selon le mode.
    func applyGridLayout() {
        galleryLayout.columnWidth = galleryColumnWidth
        let wanted: NSCollectionViewLayout = viewMode == .gallery ? galleryLayout : flowLayout
        if collectionView.collectionViewLayout !== wanted { collectionView.collectionViewLayout = wanted }
    }

    func galleryItem(at indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: GalleryItem.identifier, for: indexPath)
        if let tile = cell as? GalleryItem, items.indices.contains(indexPath.item) {
            let item = items[indexPath.item]
            tile.configure(with: item, width: galleryColumnWidth, dimmed: item.isHidden || cutPaths.contains(item.url.normalizedPath)) { [weak self] in
                self?.galleryLayout.invalidateSoon()
            }
        }
        return cell
    }

    /// Lit les dimensions des images du dossier (en-têtes seulement) puis remet la mosaïque en page.
    func loadGalleryRatios() {
        let urls = items.filter { !$0.isNavigableDirectory && !$0.url.isRemote }.map(\.url)
            .filter { ImageRatios.shared.ratio(of: $0) == nil && ImageRatios.isImage($0) }
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (index, url) in urls.enumerated() {
                ImageRatios.shared.measure(url)
                // Par paquets : les premières images se placent sans attendre tout le dossier.
                if index % 100 == 99 || index == urls.count - 1 {
                    DispatchQueue.main.async { self?.galleryLayout.invalidateSoon() }
                }
            }
        }
    }
}

/// Proportions (hauteur / largeur) des images, lues dans leurs en-têtes et gardées pour la session.
final class ImageRatios: @unchecked Sendable {
    static let shared = ImageRatios()
    private var ratios: [String: CGFloat] = [:]
    private let lock = NSLock()

    static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? false
    }

    func ratio(of url: URL) -> CGFloat? {
        lock.withLock { ratios[url.path] }
    }

    func set(_ ratio: CGFloat, for url: URL) {
        lock.withLock { ratios[url.path] = min(max(ratio, 0.25), 4) }
    }

    func measure(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, width > 0,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, height > 0 else { return }
        // Orientations EXIF 5 à 8 : l'image s'affiche tournée d'un quart de tour.
        let rotated = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        set(rotated ? width / height : height / width, for: url)
    }
}

/// Colonnes de même largeur ; chaque élément va dans la colonne la plus courte.
final class MasonryLayout: NSCollectionViewLayout {
    var columnWidth: CGFloat = 200 { didSet { if columnWidth != oldValue { invalidateLayout() } } }
    /// Hauteur / largeur de l'élément (1 tant qu'elle est inconnue).
    var aspectRatio: (Int) -> CGFloat = { _ in 1 }
    private let spacing: CGFloat = 8
    private let inset: CGFloat = 12
    private var frames: [NSRect] = []
    private var contentHeight: CGFloat = 0
    private var invalidationPending = false

    /// Regroupe les remises en page demandées par les vignettes et les dimensions qui arrivent.
    func invalidateSoon() {
        guard !invalidationPending else { return }
        invalidationPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.invalidationPending = false
            self?.invalidateLayout()
        }
    }

    override func prepare() {
        super.prepare()
        frames = []
        guard let collectionView, collectionView.numberOfSections > 0 else { contentHeight = 0; return }
        let available = collectionView.bounds.width - 2 * inset
        let count = max(1, Int((available + spacing) / (columnWidth + spacing)))
        let width = ((available - CGFloat(count - 1) * spacing) / CGFloat(count)).rounded(.down)
        var heights = [CGFloat](repeating: inset, count: count)
        for index in 0..<collectionView.numberOfItems(inSection: 0) {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let height = (width * aspectRatio(index)).rounded()
            frames.append(NSRect(x: inset + CGFloat(column) * (width + spacing), y: heights[column], width: width, height: height))
            heights[column] += height + spacing
        }
        contentHeight = (heights.max() ?? inset) - spacing + inset
    }

    override var collectionViewContentSize: NSSize {
        NSSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        frames.indices.filter { frames[$0].intersects(rect) }.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.item) else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = frames[indexPath.item]
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

/// Une tuile de la galerie : l'image à bords perdus ; le nom en bandeau pour ce qui n'a pas d'aperçu.
final class GalleryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("GalleryItem")

    private let picture = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private var representedPath = ""

    override var isSelected: Bool { didSet { refreshAppearance() } }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 8
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingMiddle
        caption.textColor = Theme.text
        for view in [picture, caption] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            picture.topAnchor.constraint(equalTo: root.topAnchor),
            picture.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            picture.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            caption.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            caption.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            caption.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
        ])
        view = root
    }

    /// `ratioChanged` : l'aperçu révèle une proportion encore inconnue (vidéo, PDF…).
    func configure(with file: FileItem, width: CGFloat, dimmed: Bool, ratioChanged: @escaping () -> Void) {
        representedPath = file.url.normalizedPath
        view.toolTip = file.name
        view.alphaValue = dimmed ? 0.5 : 1
        caption.stringValue = file.name
        showIcon(file.icon)
        refreshAppearance()

        guard !file.url.isRemote, !file.isNavigableDirectory else { return }
        let path = representedPath
        let url = file.url
        ThumbnailCache.shared.thumbnail(for: url, size: width, scale: view.window?.backingScaleFactor ?? 2) { [weak self] image in
            guard let self, representedPath == path, let image, image.size.width > 0 else { return }
            picture.image = image
            picture.imageScaling = .scaleProportionallyUpOrDown
            caption.isHidden = true
            if ImageRatios.shared.ratio(of: url) == nil {
                ImageRatios.shared.set(image.size.height / image.size.width, for: url)
                ratioChanged()
            }
        }
    }

    /// Dossier, ou fichier en attente d'aperçu : l'icône au centre et le nom dessous.
    private func showIcon(_ icon: NSImage) {
        // L'icône occupe la moitié de la tuile, au-dessus du nom.
        picture.image = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { _ in
            icon.draw(in: NSRect(x: 50, y: 64, width: 100, height: 100))
            return true
        }
        picture.imageScaling = .scaleProportionallyUpOrDown
        caption.isHidden = false
    }

    func refreshAppearance() {
        guard isViewLoaded else { return }
        let emphasized = collectionView?.window?.firstResponder === collectionView && collectionView?.window?.isKeyWindow == true
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            view.layer?.borderColor = (emphasized ? Theme.accent : Theme.inactiveSelection).cgColor
        }
        view.layer?.borderWidth = isSelected ? 3 : 0
    }
}
