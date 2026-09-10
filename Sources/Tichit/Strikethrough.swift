import Foundation

extension String {
    /// Struck-through text using the combining long stroke overlay (U+0336).
    ///
    /// Notification bodies are plain text with no styling, so the strike has to live
    /// in the characters themselves. Combining marks are skipped so an accented
    /// letter gets one stroke, not two.
    var struckThrough: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            result.unicodeScalars.append(scalar)
            let isCombining = (0x0300...0x036F).contains(scalar.value)
            if !isCombining, !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                result.unicodeScalars.append(Unicode.Scalar(0x0336)!)
            }
        }
    }
}
