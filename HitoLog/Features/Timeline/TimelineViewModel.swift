import Foundation

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published private(set) var isRefreshing = false

    func refresh(using store: AppDataStore) async {
        isRefreshing = true
        await store.refresh()
        isRefreshing = false
    }
}
