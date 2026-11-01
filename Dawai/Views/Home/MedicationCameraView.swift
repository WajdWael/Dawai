//
//  MedicationCameraView.swift
//  Dawai
//
//  Use-Case 3 (UC-3) Step 3 & Mockup Screen 6:
//  Camera and Photo Capture interface for attaching medication package or bottle images.
//

import SwiftUI
import PhotosUI

public struct MedicationCameraView: View {
    @Binding public var capturedImageData: Data?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isFrontCamera: Bool = false
    @State private var flashEffect: Bool = false
    @State private var capturedImage: UIImage? = nil
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
                        .font(.system(size: 13, weight: .bold))
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
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    processSelectedImageData(data)
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("صورة")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            // Torch / Flash Toggle dummy icon matching standard iOS camera
            Image(systemName: "bolt.circle")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
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
            } else {
                // Live Viewfinder / Simulated Scanner Frame
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 22/255, green: 24/255, blue: 28/255))
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)

                    // Subtle framing reticle guidelines
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
                    .padding(32)

                    // Center pill illustration indicator
                    VStack(spacing: 12) {
                        Image(systemName: "pill.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Color.dawaiPrimary.opacity(0.6))
                            .rotationEffect(.degrees(-45))

                        Text("وجه الكاميرا نحو عبوة الدواء")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
        }
    }

    private func cornerReticle(angle: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.white.opacity(0.8), lineWidth: 3)
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
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Main Shutter / Action Button
            if capturedImage != nil {
                // Confirm selection button
                Button {
                    if let img = capturedImage, let data = img.jpegData(compressionQuality: 0.8) {
                        capturedImageData = data
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                        Text("استخدام الصورة")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.dawaiPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                // Shutter Button (Matches Screen 6)
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
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isFrontCamera.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 22))
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
        withAnimation(.easeOut(duration: 0.15)) {
            flashEffect = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                flashEffect = false
            }
        }

        // Generate synthetic medication bottle demonstration image for simulator
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        let simulatedPhoto = renderer.image { ctx in
            // Clean dark slate background
            let rect = CGRect(x: 0, y: 0, width: 600, height: 600)
            UIColor(red: 24/255, green: 28/255, blue: 34/255, alpha: 1).setFill()
            ctx.fill(rect)

            // Bottle outline
            let bottleRect = CGRect(x: 180, y: 140, width: 240, height: 340)
            let bottlePath = UIBezierPath(roundedRect: bottleRect, cornerRadius: 36)
            UIColor(red: 0/255, green: 123/255, blue: 120/255, alpha: 0.85).setFill()
            bottlePath.fill()

            // Cap
            let capRect = CGRect(x: 230, y: 90, width: 140, height: 50)
            let capPath = UIBezierPath(roundedRect: capRect, cornerRadius: 12)
            UIColor.white.setFill()
            capPath.fill()

            // Label
            let labelRect = CGRect(x: 200, y: 220, width: 200, height: 180)
            let labelPath = UIBezierPath(roundedRect: labelRect, cornerRadius: 16)
            UIColor(white: 0.96, alpha: 1).setFill()
            labelPath.fill()

            // Pill text
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

        withAnimation {
            self.capturedImage = simulatedPhoto
        }
    }

    private func processSelectedImageData(_ data: Data) {
        // UC-3 S#4: Validate size <= 5MB
        if data.count > 5 * 1024 * 1024 {
            self.errorMessage = "حجم الصورة كبير جداً. الحد الأقصى هو 5 ميجابايت."
            return
        }

        if let image = UIImage(data: data) {
            self.capturedImage = image
            self.errorMessage = nil
        } else {
            self.errorMessage = "صيغة الصورة غير مدعومة."
        }
    }
}
