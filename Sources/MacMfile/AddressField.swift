import AppKit
import MfileCore

/// Thanh địa chỉ: hiện breadcrumb theo ngôn ngữ; khi bấm vào hoặc Cmd+L thì hiện đường dẫn thật đã bôi đen (Mục 5.13).
final class AddressField: NSTextField {
    var realPath = "/"
    var displayText = "" { didSet { if currentEditor() == nil { stringValue = displayText } } }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            stringValue = realPath
            currentEditor()?.selectAll(nil)
        }
        return ok
    }

    func restoreDisplay() {
        stringValue = displayText
    }
}
