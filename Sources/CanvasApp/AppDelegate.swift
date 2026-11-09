import AppKit
import CanvasCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: Server?
    private var lockFD: Int32 = -1
    private var sources: [DispatchSourceProtocol] = []
    private var configWatcher: ConfigWatcher?

    func applicationDidFinishLaunching(_: Notification) {
        Sock.ignoreSigPipe()
        guard acquireLock() else {
            debugLog("another server holds \(Paths.lock); exiting")
            exit(0)
        }
        NSApp.mainMenu = Self.makeMainMenu()
        let config = Config.load()
        ChannelHub.shared.persist(to: Paths.store)
        let hosts = HostPools(indexURL: Paths.webDir.appendingPathComponent("index.html"),
                              policy: WarmPolicy(config), runtime: Self.makeRuntime())
        let server = Server(hosts: hosts)
        do {
            try server.start()
        } catch {
            FileHandle.standardError.write(Data("canvas-server: could not start: \(error)\n".utf8))
            exit(1)
        }
        self.server = server
        server.registerHotkeys(global: config.hotkey)
        configWatcher = ConfigWatcher(url: Paths.config) { [weak server] text in server?.reloadConfig(text) }
        debugLog("warm policy \(config.warm.rawValue), "
                 + "linger \(config.lingerSeconds) s, idle \(config.idleMinutes) min")
        watchSignals(server)
        watchMemoryPressure(server)
        DispatchQueue.main.async { hosts.fill() }
    }

    /// Nil when `native.js` can't be loaded; every panel then uses WebKit.
    private static func makeRuntime() -> NativeRuntime? {
        do {
            return try NativeRuntime()
        } catch {
            debugLog("native renderer unavailable: \(error)")
            return nil
        }
    }

    func applicationWillTerminate(_: Notification) {
        ChannelHub.shared.flush()
        server?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { false }

    private func watchSignals(_ server: Server) {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                ChannelHub.shared.flush()
                server.stop()
                exit(0)
            }
            source.resume()
            sources.append(source)
        }
    }

    /// Under memory pressure the warm page and resting panels go; the next
    /// show builds what it needs.
    private func watchMemoryPressure(_ server: Server) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak server] in
            debugLog("memory pressure; dropping the warm page and resting panels")
            server?.hosts.trim()
            server?.dropResting()
        }
        source.resume()
        sources.append(source)
    }

    /// Held for the life of the process so two servers can't both serve the
    /// same home.
    private func acquireLock() -> Bool {
        lockFD = open(Paths.lock, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { return true }
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0
    }

    /// Without a main menu, an accessory app gets no Cmd+C/V/X/A/Z in the webview.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
