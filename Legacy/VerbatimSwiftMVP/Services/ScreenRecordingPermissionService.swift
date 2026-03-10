import CoreGraphics
import Foundation

protocol ScreenRecordingPermissionProviding: Sendable {
    func hasPermission() -> Bool
    func requestPermission() -> Bool
}

struct LiveScreenRecordingPermissionProvider: ScreenRecordingPermissionProviding {
    func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
