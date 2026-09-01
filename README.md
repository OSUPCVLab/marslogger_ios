# MARS Logger for iOS

MARS Logger records synchronized camera, ARKit pose, camera calibration, and
Core Motion data on an iPhone. The primary `MarsLogger` target is now a native
SwiftUI application built around one authoritative `ARSession`.

The repository now has one application target: the native Swift/ARKit
`MarsLogger` app. The retired CPU, Core Image, OpenCV, and Objective-C
RosyWriter paths are available in repository history if a comparison is needed.

## What the Swift application records

Each capture is stored under `Documents/MarsLogger/<ISO-8601 timestamp>/`:

```text
camera.mov   H.264 frames sourced from ARFrame.capturedImage
frames.csv   pose, intrinsics, resolution, tracking state, and timestamps
imu.csv      acceleration, rotation rate, gravity, attitude, and timestamps
```

ARKit frame timestamps and Core Motion timestamps both use device-uptime clock
semantics. Each CSV also includes an estimated Unix timestamp using the boot-time
offset measured when the writer is created.

## Why ARKit owns camera capture

The Swift migration does not run an `AVCaptureSession` beside ARKit. ARKit owns
the camera, and video is encoded directly from each `ARFrame.capturedImage`.
That keeps image, camera transform, intrinsics, tracking state, and frame time
attached to the same source frame while avoiding camera-session contention.

## Run

Requirements:

- Xcode 16 or later
- iOS 15 or later
- A physical ARKit-capable iPhone or iPad

Open `MarsLogger.xcodeproj`, select the `MarsLogger` scheme, choose your
development team and a physical device, then run.

1. Grant camera and motion permission.
2. Wait for tracking state to become `normal`.
3. Tap **Record**.
4. Move through the capture area.
5. Tap **Stop**.
6. Tap **Share Last Capture** to export the video and both CSV files.

## CSV conventions

- Matrices are written in the column-major order returned by simd/ARKit.
- Translation is in meters in ARKit's right-handed world coordinate system.
- Rotation rate is radians per second.
- User acceleration and gravity use Core Motion's `g` units.
- Locale-independent decimal formatting is used.
- Tracking limitations are recorded explicitly instead of silently dropping
  frames.

## Privacy

Captures remain in the app's Documents directory until the user exports or
deletes them. The application contains no account, analytics, network upload,
or background transmission path.

## License

GPL-3.0. See `LICENSE` and the original Apple sample terms in `LICENSE.txt`.
