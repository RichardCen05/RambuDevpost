import SwiftUI

@main
struct RambuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.lang, model.lang)
                .environment(\.locale, model.lang.locale)
                .tint(Brand.teal)
        }
    }
}
