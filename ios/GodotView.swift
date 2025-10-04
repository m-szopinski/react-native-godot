import Foundation
#if canImport(UIKit)
import UIKit
@objc(GodotView)
class GodotView: UIView {
}
#else
import AppKit
@objc(GodotView)
class GodotView: NSView {
}
#endif
