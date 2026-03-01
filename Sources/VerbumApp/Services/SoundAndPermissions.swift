import Foundation
import AppKit
import AVFoundation
import ApplicationServices

final class SystemSoundService: SoundServicing {
    func playStart() {
        NSSound.beep()
    }

    func playStop() {
        NSSound.beep()
    }
}

enum PermissionManager {
    static func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
}
