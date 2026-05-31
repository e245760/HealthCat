import SwiftUI
import SwiftData

@main
struct CatApp: App {
    // AppCoordinator をアプリ起動時に1つだけ生成し、環境経由で全 View に配布
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
        }
        .modelContainer(for: [DailyRecord.self, CollectionData.self])
    }
}
