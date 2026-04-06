import AVFoundation
import UIKit
import Photos
import CoreImage

class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var freeSpaceWarning = false
    
    let session = AVCaptureMultiCamSession()
    
    private var wideDeviceInput: AVCaptureDeviceInput?
    private var ultraWideDeviceInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    
    // Wide uses Simple Output (4K Vertical)
    private let wideOutput = AVCaptureMovieFileOutput()
    
    // UltraWide uses Data Output for custom Rotate + Crop (1080p Horizontal)
    private let ultraWideDataOutput = AVCaptureVideoDataOutput()
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var wideFileURL: URL?
    private var ultraWideFileURL: URL?
    
    private let context = CIContext()
    private var isAssetWriterReady = false
    private let recordingQueue = DispatchQueue(label: "com.multicam.recording", qos: .userInitiated)
    
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
        
        // 4. Wide Output (MovieFileOutput)
        if session.canAddOutput(wideOutput) {
            session.addOutputWithNoConnections(wideOutput)
        }
        
        // 5. UltraWide Output (VideoDataOutput)
        if session.canAddOutput(ultraWideDataOutput) {
            ultraWideDataOutput.setSampleBufferDelegate(self, queue: recordingQueue)
            session.addOutputWithNoConnections(ultraWideDataOutput)
        }
        
        // Connections
        if let wideVideoPort = wideDeviceInput?.ports.first(where: { $0.mediaType == .video }),
           session.canAddConnection(AVCaptureConnection(inputPorts: [wideVideoPort], output: wideOutput)) {
            let connection = AVCaptureConnection(inputPorts: [wideVideoPort], output: wideOutput)
            connection.videoOrientation = .portrait
            session.addConnection(connection)
        }
        
        if let ultraWideVideoPort = ultraWideDeviceInput?.ports.first(where: { $0.mediaType == .video }),
           session.canAddConnection(AVCaptureConnection(inputPorts: [ultraWideVideoPort], output: ultraWideDataOutput)) {
            let connection = AVCaptureConnection(inputPorts: [ultraWideVideoPort], output: ultraWideDataOutput)
            // Keep buffer orientation as-is, we will rotate manually in delegate
            connection.videoOrientation = .portrait
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
        ultraWideFileURL = generateFileName(type: "ultrawide_1080_cropped")
        
        setupAssetWriter(url: ultraWideFileURL!)
        
        wideOutput.startRecording(to: wideFileURL!, recordingDelegate: self)
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    func setupAssetWriter(url: URL) {
        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
            ]
            
            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            assetWriterInput?.expectsMediaDataInRealTime = true
            
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080
            ]
            
            assetWriterPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterInput!,
                sourcePixelBufferAttributes: attributes
            )
            
            if assetWriter!.canAdd(assetWriterInput!) {
                assetWriter!.add(assetWriterInput!)
            }
            
            isAssetWriterReady = false
        } catch {
            print("Failed to setup AssetWriter: \(error)")
        }
    }
    
    func stopRecording() {
        wideOutput.stopRecording()
        
        recordingQueue.async {
            self.isRecording = false
            if self.assetWriter?.status == .writing {
                self.assetWriterInput?.markAsFinished()
                self.assetWriter?.finishWriting {
                    StorageManager.saveVideo(url: self.ultraWideFileURL!)
                }
            }
        }
    }
    
    // MARK: - Delegates
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
            return
        }
        StorageManager.saveVideo(url: outputFileURL)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording, let assetWriter = assetWriter else { return }
        
        if !isAssetWriterReady {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            isAssetWriterReady = true
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              assetWriterInput?.isReadyForMoreMediaData == true else { return }
        
        // Process Frame: Rotate + Crop
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        
        // 1. Rotate 90 degrees (Portrait -> Landscape)
        // If device is vertical, we rotate right to make it a horizontal feed
        let rotated = ciImage.oriented(.right)
        
        // 2. Crop to 16:9
        // Original rotated bounds
        let fullWidth = rotated.extent.width
        let fullHeight = rotated.extent.height
        
        let targetWidth = fullWidth
        let targetHeight = fullWidth * (9.0 / 16.0)
        let yOffset = (fullHeight - targetHeight) / 2.0
        
        let cropRect = CGRect(x: 0, y: yOffset, width: targetWidth, height: targetHeight)
        let cropped = rotated.cropped(to: cropRect)
        
        // 3. Scale to 1080p
        let scaleX = 1920.0 / cropped.extent.width
        let scaleY = 1080.0 / cropped.extent.height
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Render to Pixel Buffer
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterPixelBufferAdaptor!.pixelBufferPool!, &pixelBuffer)
        
        if let pb = pixelBuffer {
            context.render(scaled, to: pb)
            assetWriterPixelBufferAdaptor?.append(pb, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
    }
}
