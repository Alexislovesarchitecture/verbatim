import Foundation
#if canImport(AppKit)
import AppKit
#endif

protocol SoundCueServiceProtocol {
    func playStartCue()
    func playStopCue()
}

final class SoundCueService: SoundCueServiceProtocol {
    func playStartCue() {
#if canImport(AppKit)
        if let sound = NSSound(named: NSSound.Name("Pop")) {
            sound.play()
        } else {
            NSSound.beep()
        }
#endif
    }

    func playStopCue() {
#if canImport(AppKit)
        if let sound = NSSound(named: NSSound.Name("Submarine")) {
            sound.play()
        } else {
            NSSound.beep()
        }
#endif
    }
}
