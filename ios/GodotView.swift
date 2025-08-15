import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformView = UIView
#else
import AppKit
public typealias PlatformView = NSView
#endif

// MARK: - Adapter / Bridge

@objc protocol GodotEngine: AnyObject {
    func initialize(project: String?)
    func contentView() -> PlatformView?
    func changeScene(path: String)
    func sendEvent(_ name: String)
}

final class StubGodotEngine: GodotEngine {
    private var inited = false
    var suppressStubLogs: Bool = false
    private var envSuppress: Bool {
        ProcessInfo.processInfo.environment["RN_GODOT_SUPPRESS_STUB_LOGS"] == "1"
    }
    private var suppress: Bool { suppressStubLogs || envSuppress }
    func initialize(project: String?) {
        if !inited && !suppress {
            print("[GodotBridge] (stub) initialize (project=\(project ?? "nil")). Brak integracji – zobacz README.")
        }
        inited = true
    }
    func contentView() -> PlatformView? {
        #if canImport(UIKit)
        let v = UIView()
        let label = UILabel()
        label.text = "Stub Godot Engine – brak integracji"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
        #else
        let v = NSView()
        let label = NSTextField(labelWithString: "Stub Godot Engine – brak integracji")
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
        #endif
    }
    func changeScene(path: String) {
        if !suppress { print("[GodotBridge] (stub) changeScene(\(path)) – ignoruję.") }
    }
    func sendEvent(_ name: String) {
        if !suppress { print("[GodotBridge] (stub) sendEvent(\(name)) – ignoruję.") }
    }
}

enum GodotBridge {
    private static var _engine: GodotEngine = StubGodotEngine()
    static var engine: GodotEngine { _engine }
    @discardableResult
    static func setEngine(_ engine: GodotEngine) -> GodotEngine {
        _engine = engine
        return engine
    }
}

@objc(GodotView)
class GodotView: PlatformView {

    @objc var projectPath: String? {
        didSet { startEngineIfNeeded() }
    }
    @objc var mainScene: String? {
        didSet {
            if engineStarted, let scene = mainScene {
                log("Zmiana sceny -> \(scene)")
                GodotBridge.engine.changeScene(path: scene)
            }
        }
    }
    @objc var symbolPrefix: String? {
        didSet { if !engineStarted && autoStartFlag { startEngineIfNeeded() } }
    }
    @objc var symbolPrefixes: String? {
        didSet { if !engineStarted && autoStartFlag { startEngineIfNeeded() } }
    }
    @objc var suppressStubLogs: NSNumber? {
        didSet {
            if let stub = GodotBridge.engine as? StubGodotEngine {
                stub.suppressStubLogs = suppressStubLogs?.boolValue ?? false
            }
        }
    }
    @objc var autoStart: NSNumber? {
        didSet {
            autoStartFlag = autoStart?.boolValue ?? true
            if autoStartFlag { startEngineIfNeeded() }
        }
    }

    private var autoStartFlag: Bool = true
    private var engineStarted = false
    private var pendingEvents: [String] = []
    private var stubInfoLogged = false

    private func log(_ msg: String) { print("[GodotView] \(msg)") }

    // --- Helpers (pozostają – ale bez fallbacków demo) ---

    private func parseMainScene(from projectRoot: String) -> String? {
        let path = (projectRoot as NSString).appendingPathComponent("project.godot")
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for rawLine in data.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("run/main_scene=") else { continue }
            if let v = line.split(separator: "=", maxSplits: 1).last {
                var value = String(v).trimmingCharacters(in: .whitespacesAndNewlines)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return value
            }
        }
        return nil
    }

    private func resolveUIDScene(_ uidValue: String, projectRoot: String) -> String? {
        guard uidValue.hasPrefix("uid://") else { return nil }
        let target = uidValue.replacingOccurrences(of: "uid://", with: "")
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: projectRoot) else { return nil }
        while let e = en.nextObject() as? String {
            if e.lowercased().hasSuffix(".tscn") {
                let full = (projectRoot as NSString).appendingPathComponent(e)
                if let chunk = try? String(contentsOfFile: full, encoding: .utf8).prefix(512),
                   chunk.contains("uid://\(target)") {
                    log("Zmapowano UID \(target) -> \(e)")
                    return "res://\(e.replacingOccurrences(of: "\\", with: "/"))"
                }
            }
        }
        return nil
    }

    // MARK: - Rozszerzona diagnostyka project.godot

    private func logProjectScan(_ msg: String) {
        print("[GodotView][project-scan] \(msg)")
    }

    // Zbiera kandydatów bundle do zeskanowania
    private func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        bundles.append(Bundle.main)
        bundles.append(Bundle(for: GodotView.self))
        // Dodaj wszystkie – filtrowane potem po ścieżce
        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(contentsOf: Bundle.allFrameworks)
        // Dedup po resourceURL.path
        var seen = Set<String>()
        var out: [Bundle] = []
        for b in bundles {
            if let p = b.resourceURL?.path, !seen.contains(p) {
                seen.insert(p)
                out.append(b)
            }
        }
        return out
    }

    // Zwraca katalog projektu jeśli znajdzie `godot-project/project.godot`
    private func locateDefaultProjectDir() -> String? {
        let bundles = candidateBundles()
        logProjectScan("Skanuję \(bundles.count) bundles w poszukiwaniu godot-project/project.godot")
        for b in bundles {
            guard let root = b.resourceURL?.path else { continue }
            let candidate = (root as NSString).appendingPathComponent("godot-project")
            let projectFile = (candidate as NSString).appendingPathComponent("project.godot")
            if FileManager.default.fileExists(atPath: projectFile) {
                logProjectScan("Znaleziono: \(projectFile)")
                return candidate
            } else {
                // Log tylko w trybie debug (ENV w Xcode: GODOT_VERBOSE_PROJECT_SCAN=1)
                if ProcessInfo.processInfo.environment["GODOT_VERBOSE_PROJECT_SCAN"] == "1" {
                    logProjectScan("Brak w: \(projectFile)")
                }
            }
        }
        logProjectScan("Nie znaleziono żadnego domyślnego projektu.")
        return nil
    }

    private func resolveProjectPath(_ explicit: String?) -> String? {
        let fm = FileManager.default

        // 1. Jawnie podana ścieżka absolutna
        if let p = explicit, p.hasPrefix("/"), fm.fileExists(atPath: p) {
            log("Używam absolutnej ścieżki: \(p)")
            return p
        }
        // 2. Jawna ścieżka względna – spróbuj w main bundle
        if let p = explicit, !p.hasPrefix("/"), let base = Bundle.main.resourceURL {
            let cand = base.appendingPathComponent(p).path
            if fm.fileExists(atPath: cand) {
                log("Znaleziono w bundle (projectPath): \(cand)")
                return cand
            } else {
                log("Nie znaleziono projektu podanego w props (projectPath=\(p)).")
            }
        } else if explicit != nil {
            log("Nie znaleziono projektu (projectPath=\(explicit ?? "nil")).")
        }

        // 3. Fallback: wyszukaj domyślny projekt
        if let def = locateDefaultProjectDir() {
            return def
        }

        // 4. Brak
        log("Brak projektu – uruchamiam silnik bez wskazania project.godot.")
        log("UWAGA: jeśli widzisz animowane (tęczowe) tło, nadal używasz placeholdera (godot_embed.example.mm). Skopiuj go jako godot_embed.mm i zaimplementuj realny bootstrap Godot + dodaj resources (podspec: s.resources = [\"godot-project/**/*\"].)")
        return nil
    }

    private func findPck(in root: String) -> String? {
        let fm = FileManager.default
        if root.hasSuffix(".pck"), fm.fileExists(atPath: root) { return root }
        if let list = try? fm.contentsOfDirectory(atPath: root),
           let pck = list.first(where: { $0.lowercased().hasSuffix(".pck") }) {
            let full = (root as NSString).appendingPathComponent(pck)
            log("Wykryto .pck: \(full)")
            return full
        }
        return nil
    }

    // --- Public API ---

    @objc func ensureEngine() { startEngineIfNeeded(forced: true) }
    @objc func retryStart() { ensureEngine() }
    @objc func diagnoseStub() {
        let needed = RNGodotEngineRegistry.requiredSymbols(prefix: symbolPrefix).joined(separator: ", ")
        log("Stub – wymagane symbole: \(needed)")
    }

    @objc func receiveEventFromReact(event: String) {
        if !engineStarted {
            pendingEvents.append(event)
            if autoStartFlag { startEngineIfNeeded() }
            return
        }
        GodotBridge.engine.sendEvent(event)
    }

    @objc func setSceneFromReact(_ scene: String) {
        if engineStarted {
            log("JS setScene -> \(scene)")
            mainScene = scene
            GodotBridge.engine.changeScene(path: scene)
        } else {
            mainScene = scene
            if autoStartFlag { startEngineIfNeeded() }
        }
    }

    // NOWE: ręczne wymuszenie podłączenia widoku renderera (naprawia błąd: brak metody forceAttachRenderView)
    @objc func forceAttachRenderView() {
        // Upewnij się, że silnik wystartował (jeśli nie – spróbuj)
        if !engineStarted {
            ensureEngine()
        }
        if let real = GodotBridge.engine as? RealGodotEngine {
            real.forceAttachView()
            if let content = real.attachedViewIfAny(), content.superview !== self {
                content.frame = bounds
                #if canImport(UIKit)
                content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                #else
                content.autoresizingMask = [.width, .height]
                #endif
                addSubview(content)
                log("forceAttachRenderView: widok renderera dodany.")
            } else if real.attachedViewIfAny() != nil {
                log("forceAttachRenderView: widok już podłączony.")
            } else {
                log("forceAttachRenderView: nadal brak widoku (rn_godot_get_view == nil).")
            }
        } else {
            log("forceAttachRenderView: RealGodotEngine nieaktywny (stub?).")
        }
    }

    private func flushPendingEvents() {
        guard !pendingEvents.isEmpty else { return }
        log("Flush \(pendingEvents.count) eventów.")
        pendingEvents.forEach { GodotBridge.engine.sendEvent($0) }
        pendingEvents.removeAll()
    }

    // --- Start ---

    private func startEngineIfNeeded(forced: Bool = false) {
        guard !engineStarted || forced else { return }
        if let stub = GodotBridge.engine as? StubGodotEngine {
            stub.suppressStubLogs = suppressStubLogs?.boolValue ?? false
        }
        if !autoStartFlag && !forced { return }

        // Wymuszenie RealGodotEngine (link-time)
        GodotAutoInjector.tryInjectOnce()

        if GodotBridge.engine is StubGodotEngine && !stubInfoLogged {
            let needed = RNGodotEngineRegistry.requiredSymbols(prefix: "rn_godot_").joined(separator: ", ")
            log("Stub aktywny – brak zlinkowanych symboli: \(needed)")
            stubInfoLogged = true
        }

        log("Start silnika (engine=\(type(of: GodotBridge.engine)))")

        let basePath = resolveProjectPath(projectPath)
        let pckPath = basePath.flatMap { findPck(in: $0) }

        if let pck = pckPath {
            GodotBridge.engine.initialize(project: pck)
        } else if let folder = basePath {
            GodotBridge.engine.initialize(project: folder)
            if mainScene == nil, let autoScene = parseMainScene(from: folder) {
                if autoScene.hasPrefix("res://") {
                    mainScene = autoScene
                } else if autoScene.hasPrefix("uid://"),
                          let resolved = resolveUIDScene(autoScene, projectRoot: folder) {
                    mainScene = resolved
                }
            }
        } else {
            GodotBridge.engine.initialize(project: nil)
        }

        if let real = GodotBridge.engine as? RealGodotEngine,
           let content = real.attachedViewIfAny() {
            content.frame = bounds
            #if canImport(UIKit)
            content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            #else
            content.autoresizingMask = [.width, .height]
            #endif
            addSubview(content)
        } else if let content = GodotBridge.engine.contentView() {
            content.frame = bounds
            #if canImport(UIKit)
            content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            #else
            content.autoresizingMask = [.width, .height]
            #endif
            addSubview(content)
        } else if GodotBridge.engine is RealGodotEngine {
            log("RealGodotEngine aktywny – brak widoku (rn_godot_get_view zwraca nil).")
        }

        if let scene = mainScene {
            GodotBridge.engine.changeScene(path: scene)
        }

        flushPendingEvents()
        engineStarted = true
    }
}
// EOF
