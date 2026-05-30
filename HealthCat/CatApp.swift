import SwiftUI
import SwiftData

@main
struct CatApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [DailyRecord.self, CollectionData.self])
    }
}
