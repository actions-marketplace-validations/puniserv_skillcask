import SwiftUI

/// Placeholder root while the interface is rebuilt layer by layer; replaced by the main window scene.
public struct RootView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Skillcask",
            systemImage: "shippingbox",
            description: Text("The new interface is being built.")
        )
        .frame(minWidth: 960, minHeight: 600)
    }
}
