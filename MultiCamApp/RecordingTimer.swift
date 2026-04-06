import Foundation

class RecordingTimer: ObservableObject {
    var timer: Timer?
    @Published var seconds = 0

    func start() {
        seconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.seconds += 1
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    func formattedTime() -> String {
        let min = seconds / 60
        let sec = seconds % 60
        return String(format: "%02d:%02d", min, sec)
    }
}
