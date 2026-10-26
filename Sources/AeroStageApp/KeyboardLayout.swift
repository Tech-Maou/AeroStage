import AeroStageCore
import Carbon

/// The keyboard layout currently selected in macOS.
enum KeyboardLayout {
    /// Input source ID, e.g. `com.apple.keylayout.German`.
    static var currentID: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// Localized name, e.g. "German".
    static var currentName: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static var suggestedPreset: KeyboardPreset {
        KeyboardPreset.suggested(forLayoutID: currentID)
    }
}
