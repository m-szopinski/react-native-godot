import Foundation
import React

@objc(GodotViewManager)
class GodotViewManager: RCTViewManager {

  override static func requiresMainQueueSetup() -> Bool {
      return true
  }

  override func view() -> NSView! {
      return GodotView(frame: .zero)
  }

  @objc func sendEventToGodot(_ reactTag: NSNumber, event: NSString) {
      DispatchQueue.main.async {
          if let view = self.bridge.uiManager.view(forReactTag: reactTag) as? GodotView {
              view.receiveEventFromReact(event: event as String)
          }
      }
  }
}
