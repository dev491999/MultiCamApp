import AVFoundation
import UIKit
import Photos

class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var freeSpaceWarning = false
    
    let session = AVCaptureMultiCamSession()
    
    private var wideDeviceInput: AVCaptureDeviceInput?
    private var ultraWideDeviceInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    
    private let wideOutput = AVCaptureMovieFileOutput()
    private let ultraWideOutput = AVCaptureMovieFileOutput()
    
    private var wideFileURL: URL?
    private var ultraWideFileURL: URL?
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async { self.setupSession() }
                }
            }
        default:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access denied."
            }
        }
    }
    
    func setupSession() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            DispatchQueue.main.async {
                self.errorMessage = "MultiCam not supported on this device."
            }
            return
        }
        
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // 1. Wide camera (Back)
        guard let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { self.errorMessage = "Wide angle camera not found." }
            return
        }
        do {
            wideDeviceInput = try AVCaptureDeviceInput(device: wideCamera)
            if session.canAddInput(wideDeviceInput!) {
                session.addInputWithNoConnections(wideDeviceInput!)
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = "Failed to attach wide camera." }
            return
        }
        
        // 2. Ultra-wide camera (Back)
        guard let ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { self.errorMessage = "Ultra wide camera not found." }
            return
        }
        do {
            ultraWideDeviceInput = try AVCaptureDeviceInput(device: ultraWideCamera)
            if session.canAddInput(ultraWideDeviceInput!) {
                session.addInputWithNoConnections(ultraWideDeviceInput!)
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = "Failed to attach ultra wide camera." }
            return
        }
        
        // 3. Audio
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            self.audioInput = audioInput
            session.addInputWithNoConnections(audioInput)
        }
        
        // 4. Outputs
        if session.canAddOutput(wideOutput) {
            session.addOutputWithNoConnections(wideOutput)
        }
        if session.canAddOutput(ultraWideOutput) {
            session.addOutputWithNoConnections(ultraWideOutput)
        }
        
        // Connections
        if let wideVideoPort = wideDeviceInput?.ports.first(where: { $0.mediaType == .video }),
           session.canAddConnection(AVCaptureConnection(inputPorts: [wideVideoPort], output: wideOutput)) {
            let connection = AVCaptureConnection(inputPorts: [wideVideoPort], output: wideOutput)
            connection.videoOrientation = .portrait
            session.addConnection(connection)
        }
        
        if let ultraWideVideoPort = ultraWideDeviceInput?.ports.first(where: { $0.mediaType == .video }),
           session.canAddConnection(AVCaptureConnection(inputPorts: [ultraWideVideoPort], output: ultraWideOutput)) {
            let connection = AVCaptureConnection(inputPorts: [ultraWideVideoPort], output: ultraWideOutput)
            connection.videoOrientation = .landscapeRight
            session.addConnection(connection)
        }
        
        if let audioPort = audioInput?.ports.first(where: { $0.mediaType == .audio }),
           session.canAddConnection(AVCaptureConnection(inputPorts: [audioPort], output: wideOutput)) {
            let connection = AVCaptureConnection(inputPorts: [audioPort], output: wideOutput)
            session.addConnection(connection)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    func generateFileName(type: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: Date())
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return path.appendingPathComponent("\(name)_\(type).mp4")
    }
    
    func startRecording() {
        let free = StorageMonitor.getFreeSpace()
        if free < 5 {
            self.freeSpaceWarning = true
            return
        }
        
        wideFileURL = generateFileName(type: "wide_4k")
        ultraWideFileURL = generateFileName(type: "ultrawide_1080")
        
        wideOutput.startRecording(to: wideFileURL!, recordingDelegate: self)
        ultraWideOutput.startRecording(to: ultraWideFileURL!, recordingDelegate: self)
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    func stopRecording() {
        wideOutput.stopRecording()
        ultraWideOutput.stopRecording()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
            return
        }
        StorageManager.saveVideo(url: outputFileURL)
    }
}
