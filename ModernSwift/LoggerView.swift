import ARKit
import SwiftUI

struct LoggerView: View {
    @StateObject private var controller = CaptureController()
    @State private var showingShare = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARSessionPreview(session: controller.session)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    metric("Tracking", controller.trackingState)
                    Spacer()
                    metric("Frames", "\(controller.frameCount)")
                    Spacer()
                    metric("IMU", "\(controller.motionCount)")
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                if let error = controller.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle("Lock focus", isOn: Binding(
                    get: { controller.isFocusLocked },
                    set: { controller.setFocusLocked($0) }
                ))
                .font(.footnote)
                .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    Button(controller.isRecording ? "Stop" : "Record") {
                        controller.isRecording ? controller.stopRecording() : controller.startRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.isRecording ? .red : .blue)

                    Button("Share Last Capture") {
                        showingShare = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.lastCaptureFiles.isEmpty || controller.isRecording)
                }
            }
            .padding()
        }
        .task { controller.startSession() }
        .onDisappear { controller.stopSession() }
        .sheet(isPresented: $showingShare) {
            ActivityView(items: controller.lastCaptureFiles)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced)).lineLimit(1)
        }
    }
}

private struct ARSessionPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = true
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if view.session !== session { view.session = session }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
