import SwiftUI

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var timer = RecordingTimer()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let error = cameraManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                PreviewView(session: cameraManager.session)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    HStack {
                        Spacer()
                        if cameraManager.isRecording {
                            Text(timer.formattedTime())
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                                .padding()
                        }
                    }
                    Spacer()
                    
                    if cameraManager.freeSpaceWarning {
                        Text("Storage Space Low (< 5GB)")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        if cameraManager.isRecording {
                            cameraManager.stopRecording()
                            timer.stop()
                        } else {
                            cameraManager.startRecording()
                            timer.start()
                        }
                    }) {
                        Circle()
                            .fill(cameraManager.isRecording ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                                    .frame(width: 60, height: 60)
                            )
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            ThermalMonitor.startMonitoring {
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                    timer.stop()
                }
            }
        }
    }
}
