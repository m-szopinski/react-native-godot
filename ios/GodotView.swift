import AppKit
import Godot

@objc(GodotView)
class GodotView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGodot()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGodot()
    }

    func setupGodot() {
        Godot.initEngine()
        if let godotContentView = Godot.getContentView() {
            godotContentView.frame = self.bounds
            godotContentView.autoresizingMask = [.width, .height]
            self.addSubview(godotContentView)
        }
    }

    func receiveEventFromReact(event: String) {
        Godot.call("onReactEvent", args: [event])
    }
}
