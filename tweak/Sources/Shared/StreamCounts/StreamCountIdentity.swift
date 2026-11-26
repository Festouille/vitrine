import UIKit

@objc(SGStreamCountIdentity)
final class SGStreamCountIdentity: NSObject {
    private static func fields(_ value: Any) -> [Mirror.Child] {
        var mirror: Mirror? = Mirror(reflecting: value)
        var result: [Mirror.Child] = []
        while let current = mirror {
            result.append(contentsOf: current.children)
            mirror = current.superclassMirror
        }
        return result
    }

    private static func trackURI(_ value: Any, album: Bool, depth: Int) -> String? {
        guard depth > 0 else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.flatMap { trackURI($0.value, album: album, depth: depth - 1) }
        }
        for child in fields(value) {
            switch child.label {
            case "creativeWorkURL" where album, "entityURI", "entityUri", "trackURI":
                if let url = child.value as? URL, url.absoluteString.hasPrefix("spotify:track:") {
                    return url.absoluteString
                }
            case "url" where !album:
                if let url = child.value as? URL, url.absoluteString.hasPrefix("spotify:track:") {
                    return url.absoluteString
                }
            case "props", "creativeWork", "fadedCreativeWork", "item":
                if let uri = trackURI(child.value, album: album, depth: depth - 1) { return uri }
            default:
                break
            }
        }
        return nil
    }

    @objc(trackURIInView:album:)
    static func trackURI(in view: UIView, album: Bool) -> String? {
        let name = NSStringFromClass(type(of: view))
        guard name.contains("ElementView") || name.contains("RetrievalRowElementUI") else { return nil }
        return trackURI(view, album: album, depth: 6)
    }

    @objc(trackURIForPlaylistIdentifier:)
    static func trackURI(forPlaylistIdentifier identifier: Any) -> String? {
        let unboxed = (identifier as? AnyHashable)?.base ?? identifier
        guard let track = Mirror(reflecting: unboxed).children.first, track.label == "playlistTrack",
              let url = Mirror(reflecting: track.value).children.first(where: { $0.label == "track" })?.value as? URL
        else { return nil }
        return url.absoluteString
    }
}
