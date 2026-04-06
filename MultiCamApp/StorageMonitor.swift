import Foundation

class StorageMonitor {
    static func getFreeSpace() -> Double {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSize = attrs[.systemFreeSize] as? NSNumber {
            return freeSize.doubleValue / 1024 / 1024 / 1024
        }
        return 0
    }
}
