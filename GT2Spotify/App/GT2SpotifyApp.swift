@preconcurrency import AVFoundation
import SwiftUI
import UIKit

@main
@MainActor
struct GT2SpotifyApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView(viewModel: container.dashboardViewModel)
                    .tabItem { Label("Spotify", systemImage: "music.note") }
                BluetoothDashboardView(controller: container.bluetoothController)
                    .tabItem { Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right") }
                HuaweiQRPairingView()
                    .tabItem { Label("Pair QR", systemImage: "qrcode.viewfinder") }
            }
            .onOpenURL { url in
                container.dashboardViewModel.handleOAuthCallback(url)
            }
        }
    }
}

@MainActor
private struct HuaweiQRPairingView: View {
    @State private var isPresentingScanner = false
    @State private var payload = ""
    @State private var scannerError: String?
    @Environment(\.openURL) private var openURL

    private var payloadURL: URL? {
        guard let url = URL(string: payload), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Huawei Watch QR pairing") {
                    Text("Huawei officially supports pairing its watches with iPhone by showing a QR code on the watch and scanning it from Huawei Health. This screen captures the same QR payload for Gate 0 diagnostics, but it does not imitate Huawei Health authentication.")
                        .foregroundStyle(.secondary)

                    Button("Scan QR shown on watch") { isPresentingScanner = true }

                    if let scannerError {
                        Text(scannerError).foregroundStyle(.red)
                    }
                }

                Section("Captured QR payload") {
                    if payload.isEmpty {
                        Text("No QR captured yet.").foregroundStyle(.secondary)
                    } else {
                        Text(payload).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Copy payload") { UIPasteboard.general.string = payload }
                        if let payloadURL {
                            Button("Open QR destination") { openURL(payloadURL) }
                        }
                    }
                }

                Section("Physical pairing flow") {
                    Text("1. In Huawei Health, remove the existing watch connection.\n2. In iPhone Settings → Bluetooth, forget both Huawei Watch entries if present.\n3. On the watch, choose pairing/connect-new-phone until the QR appears.\n4. Scan that QR here and save the payload.\n5. Open iPhone Bluetooth settings and complete the system pairing prompt.\n6. Return to the Bluetooth tab and run an unfiltered scan before opening Huawei Health again.")
                        .font(.callout)
                    Button("Open Bluetooth settings") {
                        if let url = URL(string: "App-Prefs:root=Bluetooth") {
                            openURL(url)
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }

                Section("Boundary") {
                    Text("QR capture is diagnostic only. The app does not reset the watch, forget bonds automatically, claim ownership, send Huawei packets, or perform Huawei account authentication.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pair by QR")
            .sheet(isPresented: $isPresentingScanner) {
                HuaweiQRScannerView(
                    onCode: { code in
                        payload = code
                        scannerError = nil
                        isPresentingScanner = false
                    },
                    onError: { message in
                        scannerError = message
                        isPresentingScanner = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }
}

private struct HuaweiQRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .black

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            context.coordinator.configure(in: controller)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        context.coordinator.configure(in: controller)
                    } else {
                        onError("Camera access was denied.")
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { onError("Camera access is unavailable. Enable it in Settings.") }
        @unknown default:
            DispatchQueue.main.async { onError("Unknown camera authorization state.") }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let onCode: (String) -> Void
        private let onError: (String) -> Void
        private var didFinish = false

        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        @MainActor
        func configure(in controller: UIViewController) {
            guard let device = AVCaptureDevice.default(for: .video) else {
                onError("No camera is available.")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    onError("Camera input cannot be added.")
                    return
                }
                session.addInput(input)

                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    onError("QR metadata output cannot be added.")
                    return
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]

                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = controller.view.bounds
                controller.view.layer.addSublayer(preview)

                DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
            } catch {
                onError("Camera initialization failed: \(error.localizedDescription)")
            }
        }

        func stop() {
            guard session.isRunning else { return }
            DispatchQueue.global(qos: .utility).async { [session] in session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didFinish,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue,
                  !value.isEmpty else { return }
            didFinish = true
            stop()
            onCode(value)
        }
    }
}
