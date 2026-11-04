import SwiftUI

@main
struct HexTDApp: App {
    init() {
        Progression.load()          // coeficientes do motor comum
        VsCatalog.load()            // catálogo redesenhado do Vs (progression_vs.json)
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
