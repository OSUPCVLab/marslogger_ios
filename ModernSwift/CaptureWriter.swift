import ARKit
import AVFoundation
import CoreMotion
import Foundation

final class CaptureWriter {
    let directory: URL

    private let frameHandle: FileHandle
    private let motionHandle: FileHandle
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstFrameTimestamp: TimeInterval?
    private let bootTimeUnix = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    private var isFinishing = false

    init(directory: URL) throws {
        self.directory = directory
        frameHandle = try Self.makeFile(
            at: directory.appendingPathComponent("frames.csv"),
            header: CaptureSchema.frameHeader
        )
        motionHandle = try Self.makeFile(
            at: directory.appendingPathComponent("imu.csv"),
            header: CaptureSchema.motionHeader
        )
    }

    func append(frame: ARFrame, trackingState: String) throws {
        guard !isFinishing else { return }
        if assetWriter == nil { try startVideo(with: frame) }
        guard let firstFrameTimestamp else { return }

        if let input = videoInput, let adaptor, input.isReadyForMoreMediaData {
            let presentationTime = CMTime(seconds: frame.timestamp - firstFrameTimestamp, preferredTimescale: 1_000_000_000)
            adaptor.append(frame.capturedImage, withPresentationTime: presentationTime)
        }

        let camera = frame.camera
        let transform = Self.values(camera.transform)
        let intrinsics = Self.values(camera.intrinsics)
        var values = [
            CaptureSchema.number(frame.timestamp),
            CaptureSchema.number(bootTimeUnix + frame.timestamp),
        ]
        values.append(contentsOf: transform.map { CaptureSchema.number($0) })
        values.append(contentsOf: intrinsics.map { CaptureSchema.number($0) })
        values.append(String(Int(camera.imageResolution.width)))
        values.append(String(Int(camera.imageResolution.height)))
        values.append(trackingState)
        try frameHandle.write(contentsOf: Data((values.joined(separator: ",") + "\n").utf8))
    }

    func append(motion: CMDeviceMotion) throws {
        guard !isFinishing else { return }
        let values = [
            CaptureSchema.number(motion.timestamp),
            CaptureSchema.number(bootTimeUnix + motion.timestamp),
            CaptureSchema.number(motion.userAcceleration.x),
            CaptureSchema.number(motion.userAcceleration.y),
            CaptureSchema.number(motion.userAcceleration.z),
            CaptureSchema.number(motion.rotationRate.x),
            CaptureSchema.number(motion.rotationRate.y),
            CaptureSchema.number(motion.rotationRate.z),
            CaptureSchema.number(motion.gravity.x),
            CaptureSchema.number(motion.gravity.y),
            CaptureSchema.number(motion.gravity.z),
            CaptureSchema.number(motion.attitude.quaternion.x),
            CaptureSchema.number(motion.attitude.quaternion.y),
            CaptureSchema.number(motion.attitude.quaternion.z),
            CaptureSchema.number(motion.attitude.quaternion.w),
        ]
        try motionHandle.write(contentsOf: Data((values.joined(separator: ",") + "\n").utf8))
    }

    func finish(completion: @escaping (Result<[URL], Error>) -> Void) {
        guard !isFinishing else { return }
        isFinishing = true
        do {
            try frameHandle.synchronize()
            try frameHandle.close()
            try motionHandle.synchronize()
            try motionHandle.close()
        } catch {
            completion(.failure(error))
            return
        }

        guard let writer = assetWriter else {
            completion(.success(Self.outputFiles(in: directory)))
            return
        }
        videoInput?.markAsFinished()
        writer.finishWriting {
            if let error = writer.error {
                completion(.failure(error))
            } else {
                completion(.success(Self.outputFiles(in: self.directory)))
            }
        }
    }

    private func startVideo(with frame: ARFrame) throws {
        let buffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let url = directory.appendingPathComponent("camera.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.cannotAddVideoInput }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else { throw writer.error ?? CaptureError.cannotStartVideo }
        writer.startSession(atSourceTime: .zero)
        assetWriter = writer
        videoInput = input
        self.adaptor = adaptor
        firstFrameTimestamp = frame.timestamp
    }

    private static func makeFile(at url: URL, header: String) throws -> FileHandle {
        FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    private static func outputFiles(in directory: URL) -> [URL] {
        ["camera.mov", "frames.csv", "imu.csv"]
            .map(directory.appendingPathComponent)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func values(_ matrix: simd_float4x4) -> [Float] {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    private static func values(_ matrix: simd_float3x3) -> [Float] {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2].flatMap { [$0.x, $0.y, $0.z] }
    }

    enum CaptureError: Error {
        case cannotAddVideoInput
        case cannotStartVideo
    }
}

enum CaptureSchema {
    static let frameHeader = ([
        "frame_timestamp_s", "unix_timestamp_s",
        "transform_m00", "transform_m10", "transform_m20", "transform_m30",
        "transform_m01", "transform_m11", "transform_m21", "transform_m31",
        "transform_m02", "transform_m12", "transform_m22", "transform_m32",
        "transform_m03", "transform_m13", "transform_m23", "transform_m33",
        "intrinsics_m00", "intrinsics_m10", "intrinsics_m20",
        "intrinsics_m01", "intrinsics_m11", "intrinsics_m21",
        "intrinsics_m02", "intrinsics_m12", "intrinsics_m22",
        "image_width", "image_height", "tracking_state",
    ].joined(separator: ",")) + "\n"

    static let motionHeader = ([
        "motion_timestamp_s", "unix_timestamp_s",
        "user_acceleration_x_g", "user_acceleration_y_g", "user_acceleration_z_g",
        "rotation_rate_x_rad_s", "rotation_rate_y_rad_s", "rotation_rate_z_rad_s",
        "gravity_x_g", "gravity_y_g", "gravity_z_g",
        "attitude_quaternion_x", "attitude_quaternion_y", "attitude_quaternion_z", "attitude_quaternion_w",
    ].joined(separator: ",")) + "\n"

    static func number<T: BinaryFloatingPoint>(_ value: T) -> String {
        String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }
}
