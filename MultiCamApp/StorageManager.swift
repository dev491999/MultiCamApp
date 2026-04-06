import Photos

class StorageManager {
    static func saveVideo(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    if success {
                        print("Saved video to Photos Library: \(url)")
                        try? FileManager.default.removeItem(at: url)
                    } else if let error = error {
                        print("Error saving to Photos: \(error)")
                    }
                }
            }
        }
    }
}
