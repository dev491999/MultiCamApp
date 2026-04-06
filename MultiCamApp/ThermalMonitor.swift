import Foundation

class ThermalMonitor {
    static func startMonitoring(onOverheat: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main) { _ in

            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                print("Device overheating")
                onOverheat()
            }
        }
    }
}
