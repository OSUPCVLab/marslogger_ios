import ARKit
import Combine
import CoreMotion
import Foundation

final class CaptureController: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()

    @Published private(set) var isRecording = false
    @Published private(set) var trackingState = "starting"
    @Published private(set) var frameCount = 0
    @Published private(set) var motionCount = 0
    @Published private(set) var lastCaptureFiles: [URL] = []
    @Published private(set) var errorMessage: String?
    /// Whether the camera is held at a fixed focus. ARKit owns the capture
    /// device, so this is expressed through the configuration rather than by
    /// locking an AVCaptureDevice alongside the session.
    @Published private(set) var isFocusLocked = false

    private let captureQueue = DispatchQueue(label: "edu.osu.marslogger.capture", qos: .userInitiated)
    // Core Motion delivers on an OperationQueue; ARKit's delegateQueue is a
    // DispatchQueue. The two are not interchangeable, so this is a second queue
    // rather than a cast. Serial, to keep samples in the order they arrive.
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "edu.osu.marslogger.motion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let motion = CMMotionManager()
    private var writer: CaptureWriter?
    // Retained so focus can be toggled by re-running the same configuration
    // rather than building a new one, which would discard tracking state.
    private var configuration: ARWorldTrackingConfiguration?

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = captureQueue
    }

    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            publish { self.errorMessage = "ARKit world tracking is not supported on this device." }
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = !isFocusLocked
        self.configuration = configuration
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    /// Hold the lens at a fixed focus, or return it to continuous autofocus.
    ///
    /// A moving lens changes the camera intrinsics that `ARFrame.camera`
    /// reports, so a recording made while the lens hunts carries a focal
    /// length that varies across the capture. Locking focus is what the
    /// Objective-C pipeline offered through tap-to-focus; ARKit exposes it on
    /// the configuration because the session owns the capture device and a
    /// second `AVCaptureSession` must not contend for it.
    ///
    /// The session is re-run without `.resetTracking`, so toggling focus does
    /// not discard the world map or interrupt an in-progress recording.
    func setFocusLocked(_ locked: Bool) {
        publish { self.isFocusLocked = locked }
        guard let configuration = self.configuration else { return }
        configuration.isAutoFocusEnabled = !locked
        session.run(configuration)
    }

    func stopSession() {
        if isRecording { stopRecording() }
        session.pause()
    }

    func startRecording() {
        captureQueue.async {
            do {
                let directory = try Self.newCaptureDirectory()
                self.writer = try CaptureWriter(directory: directory)
                self.startMotionUpdates()
                self.publish {
                    self.frameCount = 0
                    self.motionCount = 0
                    self.errorMessage = nil
                    self.isRecording = true
                }
            } catch {
                self.publish { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func stopRecording() {
        captureQueue.async {
            self.motion.stopDeviceMotionUpdates()
            guard let writer = self.writer else { return }
            self.writer = nil
            writer.finish { result in
                self.publish {
                    self.isRecording = false
                    switch result {
                    case .success(let files): self.lastCaptureFiles = files
                    case .failure(let error): self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state = Self.trackingDescription(frame.camera.trackingState)
        publish { self.trackingState = state }
        guard let writer else { return }
        do {
            try writer.append(frame: frame, trackingState: state)
            publish { self.frameCount += 1 }
        } catch {
            publish { self.errorMessage = error.localizedDescription }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        publish { self.errorMessage = error.localizedDescription }
    }

    private func startMotionUpdates() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100.0
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] sample, error in
            guard let self else { return }
            if let error {
                self.publish { self.errorMessage = error.localizedDescription }
                return
            }
            guard let sample else { return }
            // Hand the sample back to captureQueue before touching the writer.
            // ARKit frames are already written there, and the writer is only
            // safe because that queue serialises it; appending from the motion
            // queue would race the frame writes.
            self.captureQueue.async {
                guard let writer = self.writer else { return }
                do {
                    try writer.append(motion: sample)
                    self.publish { self.motionCount += 1 }
                } catch {
                    self.publish { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func publish(_ update: @escaping () -> Void) {
        DispatchQueue.main.async(execute: update)
    }

    private static func newCaptureDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarsLogger", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let directory = root.appendingPathComponent(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func trackingDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "normal"
        case .notAvailable: return "not_available"
        case .limited(let reason):
            switch reason {
            case .initializing: return "limited_initializing"
            case .excessiveMotion: return "limited_excessive_motion"
            case .insufficientFeatures: return "limited_insufficient_features"
            case .relocalizing: return "limited_relocalizing"
            @unknown default: return "limited_unknown"
            }
        }
    }
}
