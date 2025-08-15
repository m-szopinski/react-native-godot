import Foundation
import Darwin
#if canImport(UIKit)
import UIKit
private typealias NativeView = UIView
#else
import AppKit
private typealias NativeView = NSView
#endif

// Bezpośrednie (link-time) symbole – dostarczane przez wrapper z paczki (strong, nie weak)
@_silgen_name("rn_godot_initialize") private func rn_godot_initialize(_ path: UnsafePointer<CChar>?)
@_silgen_name("rn_godot_change_scene") private func rn_godot_change_scene(_ scene: UnsafePointer<CChar>)
@_silgen_name("rn_godot_send_event") private func rn_godot_send_event(_ evt: UnsafePointer<CChar>)
@_silgen_name("rn_godot_get_view") private func rn_godot_get_view() -> UnsafeMutableRawPointer?
// Opcjonalny (może nie istnieć – wtedy brak pętli klatek). Użyj dlsym dla bezpieczeństwa.
typealias FnFrame = @convention(c) () -> Void
private let _rn_frame: FnFrame? = {
    let h = UnsafeMutableRawPointer(bitPattern: -2)
    if let sym = dlsym(h, "rn_godot_frame") {
        return unsafeBitCast(sym, to: FnFrame.self)
    }
    return nil
}()

final class RealGodotEngine: NSObject, GodotEngine {

    private var initialized = false
    private var pendingScene: String?
    private var pendingEvents: [String] = []
    #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    #else
    private var frameTimer: Timer?
    #endif
    private var cachedContentView: PlatformView?
    private var attachRetryRemaining = 120

    static func requiredSymbolNames(prefix: String) -> [String] {
        // Zachowane dla kompatybilności z diagnostyką (prefix ignorowany bo link-time)
        ["\(prefix)initialize","\(prefix)change_scene","\(prefix)send_event","\(prefix)get_view"]
    }

    func initialize(project: String?) {
        guard !initialized else { return }
        if let p = project {
            p.withCString { rn_godot_initialize($0) }
        } else {
            rn_godot_initialize(nil)
        }
        initialized = true
        if let sc = pendingScene { changeScene(path: sc); pendingScene = nil }
        if !pendingEvents.isEmpty {
            pendingEvents.forEach { sendEvent($0) }
            pendingEvents.removeAll()
        }
        print("[RealGodotEngine] Initialized (project=\(project ?? "nil")).")
        startFrameLoopIfNeeded()
        attemptAttachIfNeeded(initial: true)
    }

    func contentView() -> PlatformView? {
        if let cv = cachedContentView { return cv }
        guard let raw = rn_godot_get_view() else { return nil }
        if !CFGetTypeIDCheck(raw) {
            print("[RealGodotEngine][WARN] rn_godot_get_view zwrócił wskaźnik niepodobny do obiektu ObjC.")
            return nil
        }
        let any = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
        if let v = any as? PlatformView {
            cachedContentView = v
            return v
        }
        print("[RealGodotEngine][WARN] Obiekt nie jest \(PlatformView.self).")
        return nil
    }

    func changeScene(path: String) {
        guard initialized else {
            pendingScene = path
            return
        }
        path.withCString { rn_godot_change_scene($0) }
    }

    func sendEvent(_ name: String) {
        guard initialized else {
            pendingEvents.append(name)
            return
        }
        name.withCString { rn_godot_send_event($0) }
    }

    @objc private func frameTick() {
        _rn_frame?()
        attemptAttachIfNeeded()
    }

    private func startFrameLoopIfNeeded() {
        guard _rn_frame != nil else { return }
        #if canImport(UIKit)
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(frameTick))
        displayLink?.add(to: .main, forMode: .common)
        #else
        guard frameTimer == nil else { return }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0,
                                          repeats: true) { [weak self] _ in
            _rn_frame?()            // CHANGED (z self?._rn_frame?())
            self?.attemptAttachIfNeeded()
        }
        #endif
        print("[RealGodotEngine] Frame loop aktywna.")
    }

    private func attemptAttachIfNeeded(initial: Bool = false) {
        guard attachRetryRemaining > 0, cachedContentView == nil else { return }
        guard let v = contentView() else {
            attachRetryRemaining -= 1
            if attachRetryRemaining == 0 {
                print("[RealGodotEngine] Nie uzyskano widoku renderera (rn_godot_get_view == nil).")
            }
            return
        }
        print("[RealGodotEngine] Render view podłączony.")
        cachedContentView = v
    }

    func forceAttachView() {
        attachRetryRemaining = max(attachRetryRemaining, 30)
        attemptAttachIfNeeded()
    }

    func attachedViewIfAny() -> PlatformView? { contentView() }

    deinit {
        #if canImport(UIKit)
        displayLink?.invalidate()
        #else
        frameTimer?.invalidate()
        #endif
    }
}

// Heurystyka poprawności wskaźnika
@inline(__always)
private func CFGetTypeIDCheck(_ ptr: UnsafeMutableRawPointer) -> Bool {
    let addr = UInt(bitPattern: ptr)
    if addr < 0x1000 { return false }
    let alignment = UInt(MemoryLayout<UnsafeRawPointer>.alignment)
    if alignment == 0 { return true }
    return (addr % alignment) == 0
}

// Auto‑injekcja – zawsze próbuje ustawić RealGodotEngine (brak potrzeby dlsym – zakładamy obecność symboli link-time)
final class GodotAutoInjector {
    private static var done = false
    static func tryInjectOnce() {
        guard !done else { return }
        done = true
        if GodotBridge.engine is RealGodotEngine { return }
        let eg = RealGodotEngine()
        GodotBridge.setEngine(eg)
        print("[GodotAutoInjector] RealGodotEngine aktywny (link-time).")
    }
    @discardableResult
    static func injectIfAvailable(prefix: String? = nil) -> Bool {
        tryInjectOnce()
        return GodotBridge.engine is RealGodotEngine
    }
}

// Rejestr / Callback (pozostaje – drobna korekta diagnostyki)
@objc public final class RNGodotEngineRegistry: NSObject {
    @objc(registerEngine:)
    public static func register(engine: AnyObject) {
        guard let eg = engine as? GodotEngine else {
            print("[RNGodotEngineRegistry] Obiekt nie implementuje GodotEngine.")
            return
        }
        GodotBridge.setEngine(eg)
        print("[RNGodotEngineRegistry] Custom engine: \(type(of: eg))")
    }

    @objc(publicCurrentEngineIsStub)
    public static func currentEngineIsStub() -> Bool {
        GodotBridge.engine is StubGodotEngine
    }

    @objc(publicDiagnose)
    public static func diagnose() {
        if GodotBridge.engine is RealGodotEngine {
            print("[RNGodotEngineRegistry] OK: RealGodotEngine.")
        } else {
            print("[RNGodotEngineRegistry] Active: \(type(of: GodotBridge.engine)). Próbuję injekcji.")
            GodotAutoInjector.tryInjectOnce()
        }
    }

    @objc(publicEnsureRealEngine:)
    public static func ensureRealEngine(prefix: String? = nil) -> Bool {
        GodotAutoInjector.injectIfAvailable(prefix: prefix)
    }

    @objc
    public static func ensureRealEngineWithFallbacks(_ prefixes: [String]) -> NSString? {
        GodotAutoInjector.tryInjectOnce()
        return GodotBridge.engine is RealGodotEngine ? (prefixes.first ?? "rn_godot_") as NSString : nil
    }

    @objc(publicRequiredSymbols:)
    public static func requiredSymbols(prefix: String?) -> [String] {
        RealGodotEngine.requiredSymbolNames(prefix: prefix ?? "rn_godot_")
    }

    @objc
    public static func registerCallbacks(
        initialize: @escaping (String?) -> Void,
        contentView: @escaping () -> PlatformView?,
        changeScene: @escaping (String) -> Void,
        sendEvent: @escaping (String) -> Void
    ) {
        let engine = CallbackGodotEngine(
            initialize: initialize,
            contentView: contentView,
            changeScene: changeScene,
            sendEvent: sendEvent
        )
        GodotBridge.setEngine(engine)
        print("[RNGodotEngineRegistry] CallbackGodotEngine aktywny.")
    }

    @objc public static func forceAttachRenderView() {
        (GodotBridge.engine as? RealGodotEngine)?.forceAttachView()
    }
}

// CallbackGodotEngine (bez zmian)
final class CallbackGodotEngine: NSObject, GodotEngine {
    private let initBlock: (String?) -> Void
    private let contentBlock: () -> PlatformView?
    private let changeSceneBlock: (String) -> Void
    private let sendEventBlock: (String) -> Void
    private var initialized = false
    init(
        initialize: @escaping (String?) -> Void,
        contentView: @escaping () -> PlatformView?,
        changeScene: @escaping (String) -> Void,
        sendEvent: @escaping (String) -> Void
    ) {
        self.initBlock = initialize
        self.contentBlock = contentView
        self.changeSceneBlock = changeScene
        self.sendEventBlock = sendEvent
        super.init()
    }
    func initialize(project: String?) {
        guard !initialized else { return }
        initBlock(project); initialized = true
    }
    func contentView() -> PlatformView? { contentBlock() }
    func changeScene(path: String) { changeSceneBlock(path) }
    func sendEvent(_ name: String) { sendEventBlock(name) }
}
