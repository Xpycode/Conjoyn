import SwiftUI
import MarkdownUI

/// Renders markdown images from a host app's **bundle** so help topics can
/// reference screenshots by filename — e.g. `![A window](shot.jpg)` — with the
/// image file bundled next to the `.md` files.
///
/// Resolution order for each image URL:
/// 1. An absolute `file://` URL → loaded directly.
/// 2. A bare/relative name → looked up as `<baseURL>/<lastPathComponent>`
///    (the bundle's resource directory).
/// 3. An asset-catalog image named after the file (without extension).
/// 4. Anything else (e.g. `http(s)://`) → handed to ``DefaultImageProvider``,
///    preserving network-image behavior.
struct BundleImageProvider: ImageProvider {
    /// The bundle's `resourceURL`, or `nil` to skip directory resolution.
    let baseURL: URL?

    func makeImage(url: URL?) -> some View {
        if let image = Self.localImage(url, baseURL: baseURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // Cap at the image's own size so small images aren't upscaled;
                // larger images shrink to fit the detail pane width.
                .frame(maxWidth: image.size.width)
        } else {
            // Remote or unresolved → default (network) provider.
            DefaultImageProvider().makeImage(url: url)
        }
    }

    static func localImage(_ url: URL?, baseURL: URL?) -> NSImage? {
        guard let url else { return nil }

        // 1. Absolute file URL.
        if url.isFileURL, let image = NSImage(contentsOf: url) {
            return image
        }

        // Skip remote URLs — let the default provider handle those.
        if let scheme = url.scheme, scheme == "http" || scheme == "https" {
            return nil
        }

        let fileName = url.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        // 2. Resolve the filename against the bundle's resource directory.
        if let baseURL {
            let candidate = baseURL.appendingPathComponent(fileName)
            if let image = NSImage(contentsOf: candidate) {
                return image
            }
        }

        // 3. Fall back to an asset-catalog image named after the file stem.
        let stem = (fileName as NSString).deletingPathExtension
        if !stem.isEmpty, let image = NSImage(named: stem) {
            return image
        }

        return nil
    }
}
