import UIKit

@objc(SGStreamFixtureElementView)
final class SGStreamFixtureElementView: UIView {
    struct Item { let url: URL }
    struct Props { let item: Item }
    private var props: Props?

    @objc(setTrackURI:)
    func setTrackURI(_ uri: String) {
        props = URL(string: uri).map { Props(item: Item(url: $0)) }
    }
}
