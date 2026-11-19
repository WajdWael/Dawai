//
//  MedicationCameraView.swift
//  Dawai
//
//  Use-Case 3 (UC-3) Step 3 & Mockup Screen 6:
//  Camera and Photo Capture interface for attaching medication package or bottle images.
//

import SwiftUI
import PhotosUI
import AVFoundation
import Combine

public struct MedicationCameraView: View {
    @Binding public var capturedImageData: Data?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraController = LiveCameraController()
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var flashEffect: Bool = false
    @State private var capturedImage: UIImage? = nil
    @State private var compressedJPEGData: Data? = nil
    @State private var showingSystemCamera: Bool = false
    @State private var errorMessage: String? = nil

    public init(capturedImageData: Binding<Data?>) {
        self._capturedImageData = capturedImageData
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Header
                topBarView
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                // MARK: - Viewfinder Area
                viewfinderSection
                    .padding(.horizontal, 24)

                Spacer()

                // MARK: - Error message banner if any
                if let err = errorMessage {
                    Text(err)
                        .dawaiFont(size: 13, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(.bottom, 12)
                }

                // MARK: - Bottom Controls Bar
                bottomControlsBar
                    .padding(.bottom, 36)
                    .padding(.horizontal, 30)
            }

            // Flash animation overlay
            if flashEffect {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            cameraController.onPhotoCaptured = { image in
                applyPickedUIImage(image)
            }
            cameraController.checkPermissionAndStart()
        }
        .onDisappear {
            cameraController.stopSession()
        }
        .sheet(isPresented: $showingSystemCamera) {
            SystemCameraPicker(isFrontCamera: cameraController.isFrontCamera) { pickedImage in
                applyPickedUIImage(pickedImage)
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { newItem in
            Task { @MainActor in
                guard let newItem else { return }
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    processSelectedImageData(data)
                } else {
                    self.errorMessage = "تعذر قراءة الصورة المختارة من الألبوم."
                }
            }
        }
    }

    // MARK: - 1. Top Bar View
    private var topBarView: some View {
        HStack {
            // Close Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .dawaiFont(size: 18, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("صورة الدواء")
                .dawaiFont(size: 18, weight: .bold)
                .foregroundStyle(.white)

            Spacer()

            // Torch / Flash Toggle
            Button {
                cameraController.isFlashEnabled.toggle()
            } label: {
                Image(systemName: cameraController.isFlashEnabled ? "bolt.circle.fill" : "bolt.circle")
                    .dawaiFont(size: 22)
                    .foregroundStyle(cameraController.isFlashEnabled ? Color.yellow : .white.opacity(0.85))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Viewfinder Section
    private var viewfinderSection: some View {
        ZStack {
            if let image = capturedImage {
                // Captured Image Preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            } else if cameraController.permissionStatus == .denied || cameraController.permissionStatus == .restricted {
                // Camera Permission Denied State -> Ask user to enable in Settings
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 22/255, green: 24/255, blue: 28/255))
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)

                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .dawaiFont(size: 46)
                            .foregroundStyle(Color.dawaiPrimary)

                        Text("الرجاء السماح بفتح الكاميرا")
                            .dawaiFont(size: 18, weight: .bold)
                            .foregroundStyle(.white)

                        Text("لتصوير عبوة الدواء مباشرة، يرجى تفعيل إذن الكاميرا لتطبيق دواء من الإعدادات، أو اختيار صورة من الألبوم بالأسفل.")
                            .dawaiFont(size: 14)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString),
                               UIApplication.shared.canOpenURL(settingsURL) {
                                UIApplication.shared.open(settingsURL)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "gearshape.fill")
                                Text("فتح الإعدادات لتفعيل الكاميرا")
                                    .dawaiFont(size: 15, weight: .bold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.dawaiPrimary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Live Camera Feed (or Simulator Fallback Frame)
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 22/255, green: 24/255, blue: 28/255))
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)

                    if cameraController.hasHardwareCamera && cameraController.permissionStatus == .authorized {
                        LiveCameraPreviewView(session: cameraController.session)
                            .frame(maxWidth: .infinity)
                            .frame(height: 380)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else if !cameraController.hasHardwareCamera {
                        // Simulator preview (iOS Simulator has no hardware camera)
                        VStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.dawaiPrimary.opacity(0.18))
                                    .frame(width: 110, height: 130)

                                Image(systemName: "pills.fill")
                                    .dawaiFont(size: 46)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }

                            Text("معاينة الكاميرا (وضع المحاكي)")
                                .dawaiFont(size: 16, weight: .bold)
                                .foregroundStyle(.white)

                            Text("محاكي Xcode لا يحتوي على كاميرا حقيقية.\nاضغط زر التصوير الأبيض بالأسفل لالتقاط صورة الدواء، أو شغّل التطبيق على جوالك لفتح الكاميرا الحقيقية.")
                                .dawaiFont(size: 13, weight: .medium)
                                .foregroundStyle(.white.opacity(0.78))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, 28)
                        }
                    } else {
                        // Waiting for user to tap Allow on permission prompt
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .dawaiFont(size: 54)
                                .foregroundStyle(Color.dawaiPrimary.opacity(0.75))

                            Text("يرجى الموافقة على إذن الكاميرا لتصوير الدواء")
                                .dawaiFont(size: 15, weight: .bold)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }

                    // Subtle framing reticle guidelines (keep geometric corners unflipped in RTL)
                    VStack {
                        HStack {
                            cornerReticle(angle: 0)
                            Spacer()
                            cornerReticle(angle: 90)
                        }
                        Spacer()
                        HStack {
                            cornerReticle(angle: -90)
                            Spacer()
                            cornerReticle(angle: 180)
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(28)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    private func cornerReticle(angle: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.white.opacity(0.85), lineWidth: 3)
        .frame(width: 20, height: 20)
        .rotationEffect(.degrees(angle))
    }

    // MARK: - 3. Bottom Controls Bar
    private var bottomControlsBar: some View {
        HStack(spacing: 0) {
            // Photo Library Picker Button
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 50, height: 50)

                    Image(systemName: "photo.on.rectangle.angled")
                        .dawaiFont(size: 22)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Main Shutter / Action Button
            if capturedImage != nil {
                // Confirm selection button
                Button {
                    if let data = compressedJPEGData ?? (capturedImage.flatMap { Self.compressAndNormalizeImage($0)?.data }) {
                        capturedImageData = data
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .dawaiFont(size: 18, weight: .bold)
                        Text("استخدام الصورة")
                            .dawaiFont(size: 16, weight: .bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.dawaiPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                // Shutter Button
                Button {
                    triggerCapture()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Flip Camera / Retake Button
            if capturedImage != nil {
                Button {
                    withAnimation {
                        capturedImage = nil
                        compressedJPEGData = nil
                    }
                    cameraController.checkPermissionAndStart()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .dawaiFont(size: 22, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        cameraController.switchCamera()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .dawaiFont(size: 22)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Image Capture & Validation (UC-3 S#3 & Alternate S#4/S#5)
    private func triggerCapture() {
        // Trigger visual flash
        withAnimation(.easeOut(duration: 0.12)) {
            flashEffect = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                flashEffect = false
            }
        }

        // 1. If live AVCaptureSession is running on a real iPhone, capture directly from the live camera
        if cameraController.hasHardwareCamera && cameraController.permissionStatus == .authorized && cameraController.isSessionRunning {
            cameraController.capturePhoto()
            return
        }

        // 2. If permission was not determined yet, request it now
        if cameraController.permissionStatus == .notDetermined {
            cameraController.checkPermissionAndStart()
            return
        }

        // 3. If hardware camera is available via UIImagePickerController fallback
        if UIImagePickerController.isSourceTypeAvailable(.camera) && cameraController.permissionStatus == .authorized {
            showingSystemCamera = true
            return
        }

        // 4. Fallback on Simulator (no physical camera): generate sample medication bottle image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        let simulatedPhoto = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: 600, height: 600)
            UIColor(red: 24/255, green: 28/255, blue: 34/255, alpha: 1).setFill()
            ctx.fill(rect)

            let bottleRect = CGRect(x: 180, y: 140, width: 240, height: 340)
            let bottlePath = UIBezierPath(roundedRect: bottleRect, cornerRadius: 36)
            UIColor(red: 0/255, green: 123/255, blue: 120/255, alpha: 0.85).setFill()
            bottlePath.fill()

            let capRect = CGRect(x: 230, y: 90, width: 140, height: 50)
            let capPath = UIBezierPath(roundedRect: capRect, cornerRadius: 12)
            UIColor.white.setFill()
            capPath.fill()

            let labelRect = CGRect(x: 200, y: 220, width: 200, height: 180)
            let labelPath = UIBezierPath(roundedRect: labelRect, cornerRadius: 16)
            UIColor(white: 0.96, alpha: 1).setFill()
            labelPath.fill()

            let text = "دواء مرخص"
            let font = UIFont.boldSystemFont(ofSize: 28)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let textSize = (text as NSString).size(withAttributes: textAttributes)
            let textPoint = CGPoint(x: 300 - textSize.width / 2, y: 290)
            (text as NSString).draw(at: textPoint, withAttributes: textAttributes)
        }

        applyPickedUIImage(simulatedPhoto)
    }

    private func processSelectedImageData(_ data: Data) {
        guard let image = UIImage(data: data) else {
            self.errorMessage = "صيغة الصورة غير مدعومة."
            return
        }
        applyPickedUIImage(image)
    }

    private func applyPickedUIImage(_ image: UIImage) {
        guard let normalized = Self.compressAndNormalizeImage(image) else {
            self.errorMessage = "تعذر معالجة الصورة المختارة."
            return
        }
        withAnimation {
            self.capturedImage = normalized.image
            self.compressedJPEGData = normalized.data
            self.errorMessage = nil
        }
    }

    /// Resizes any high-resolution camera/gallery photo to fit within `maxDimension` and compresses it as JPEG (< 1 MB),
    /// ensuring all iPhone photos are accepted without exceeding the 5 MB limit or UserDefaults storage limits.
    public static func compressAndNormalizeImage(_ image: UIImage, maxDimension: CGFloat = 900) -> (image: UIImage, data: Data)? {
        MedicationService.compressAndNormalizeImage(image, maxDimension: maxDimension)
    }
}

// MARK: - Live AVFoundation Camera Controller (Requests Permission & Streams Live Camera)
@MainActor
final class LiveCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var permissionStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var hasHardwareCamera: Bool = (AVCaptureDevice.default(for: .video) != nil)
    @Published var isSessionRunning: Bool = false
    @Published var isFrontCamera: Bool = false
    @Published var isFlashEnabled: Bool = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    var onPhotoCaptured: ((UIImage) -> Void)?

    func checkPermissionAndStart() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.permissionStatus = currentStatus
        self.hasHardwareCamera = (AVCaptureDevice.default(for: .video) != nil)

        switch currentStatus {
        case .notDetermined:
            // Immediately ask the user for camera permission when opening the camera screen
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.permissionStatus = granted ? .authorized : .denied
                    if granted {
                        self.configureAndStartSession()
                    }
                }
            }
        case .authorized:
            configureAndStartSession()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func configureAndStartSession() {
        guard hasHardwareCamera else { return }

        if !isConfigured {
            session.beginConfiguration()
            session.sessionPreset = .photo

            let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) ?? AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            session.commitConfiguration()
            isConfigured = true
        }

        if !session.isRunning {
            let captureSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
                Task { @MainActor in
                    self.isSessionRunning = captureSession.isRunning
                }
            }
        } else {
            self.isSessionRunning = true
        }
    }

    func switchCamera() {
        isFrontCamera.toggle()
        guard hasHardwareCamera, isConfigured else { return }

        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }

    func capturePhoto() {
        guard isSessionRunning else { return }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.on) && isFlashEnabled {
            settings.flashMode = .on
        } else if photoOutput.supportedFlashModes.contains(.off) {
            settings.flashMode = .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func stopSession() {
        guard session.isRunning else { return }
        let captureSession = session
        DispatchQueue.global(qos: .background).async {
            captureSession.stopRunning()
        }
        isSessionRunning = false
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }
        Task { @MainActor in
            self.onPhotoCaptured?(image)
        }
    }
}

// MARK: - Live Camera Video Preview Layer
private struct LiveCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class VideoPreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

// MARK: - Real iOS Hardware Camera Wrapper (Fallback)
private struct SystemCameraPicker: UIViewControllerRepresentable {
    let isFrontCamera: Bool
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if isFrontCamera && UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        } else if UIImagePickerController.isCameraDeviceAvailable(.rear) {
            picker.cameraDevice = .rear
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: SystemCameraPicker

        init(parent: SystemCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
