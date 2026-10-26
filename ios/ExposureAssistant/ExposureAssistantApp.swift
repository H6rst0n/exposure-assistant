import SwiftUI
import ExposureCore

@main
struct ExposureAssistantApp: App {
    @StateObject private var store = SettingsStore()
    @StateObject private var timer = TimerController()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store).environmentObject(timer).preferredColorScheme(.dark) }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings { didSet { save() } }
    @Published var saveError: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset") {
            defaults.removeObject(forKey: "settings_v1")
        }
        if let data = defaults.data(forKey: "settings_v1"), let value = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = value
        } else { settings = AppSettings() }
    }
    private func save() {
        do { defaults.set(try JSONEncoder().encode(settings), forKey: "settings_v1") }
        catch { saveError = "設定儲存失敗：\(error.localizedDescription)" }
    }
}
