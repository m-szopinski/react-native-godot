import Foundation
import React

@objc(GodotViewManager)
class GodotViewManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }

    #if canImport(UIKit)
    override func view() -> UIView! { GodotView(frame: .zero) }
    #else
    override func view() -> NSView! { GodotView(frame: .zero) }
    #endif

    @objc func sendEventToGodot(_ reactTag: NSNumber, event: NSString) {
        bridge.uiManager.addUIBlock { _, registry in
            if let v = registry?[reactTag] as? GodotView {
                v.receiveEventFromReact(event: event as String)
            }
        }
    }

    @objc func ensureEngine(_ reactTag: NSNumber) {
        bridge.uiManager.addUIBlock { _, registry in
            (registry?[reactTag] as? GodotView)?.ensureEngine()
        }
    }

    @objc func diagnoseStub(_ reactTag: NSNumber) {
        bridge.uiManager.addUIBlock { _, registry in
            (registry?[reactTag] as? GodotView)?.diagnoseStub()
        }
    }

    @objc func setScene(_ reactTag: NSNumber, scene: NSString) {
        bridge.uiManager.addUIBlock { _, registry in
            (registry?[reactTag] as? GodotView)?.setSceneFromReact(scene as String)
        }
    }

    @objc func forceAttachRenderView(_ reactTag: NSNumber) {
        bridge.uiManager.addUIBlock { _, registry in
            (registry?[reactTag] as? GodotView)?.forceAttachRenderView()
        }
    }
}
