import SwiftUI

@main
@MainActor
enum Launcher {
    static func main() {
        if Debug.handle(CommandLine.arguments) { return }
        FolgaApp.main()
    }
}

struct FolgaApp: App {
    @StateObject private var store = Store()
    @StateObject private var awake = KeepAwake()
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            RootView().environmentObject(store).environmentObject(awake).environmentObject(updater)
        } label: {
            if awake.isOn {
                Image(systemName: "cup.and.saucer.fill")
                Text(awake.compactRemaining)
            } else {
                Image(systemName: "internaldrive")
                if let disk = store.disk { Text(bytesShort(disk.available)) }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
