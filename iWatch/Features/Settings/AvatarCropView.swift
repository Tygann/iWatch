import SwiftUI

struct AvatarCropSelection: Identifiable {
    let id = UUID()
    let image: UIImage
    let ownerID: UUID
}

struct AvatarCropView: View {
    let selection: AvatarCropSelection
    let account: AccountSession
    let usePhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    @State private var horizontal = 0.0
    @State private var vertical = 0.0
    @State private var dragOrigin: CGSize?
    @State private var zoomOrigin: Double?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Drag to position. Pinch or use the zoom buttons to adjust.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    GeometryReader { geometry in
                        let side = max(1, geometry.size.width - 24)
                        let scale = max(side / selection.image.size.width, side / selection.image.size.height) * zoom
                        let width = selection.image.size.width * scale
                        let height = selection.image.size.height * scale
                        ZStack {
                            Image(uiImage: selection.image).resizable()
                                .frame(width: width, height: height)
                                .offset(x: horizontal * (width - side) / 2, y: vertical * (height - side) / 2)
                                .frame(width: side, height: side).clipped()
                            Color.black.opacity(0.45).mask {
                                Rectangle().overlay { Circle().blendMode(.destinationOut) }.compositingGroup()
                            }
                            Circle().strokeBorder(.white, lineWidth: 2)
                        }
                        .frame(width: side, height: side)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { value in
                            if dragOrigin == nil { dragOrigin = CGSize(width: horizontal, height: vertical) }
                            horizontal = clamp((dragOrigin?.width ?? 0) + value.translation.width / max((width - side) / 2, 1))
                            vertical = clamp((dragOrigin?.height ?? 0) + value.translation.height / max((height - side) / 2, 1))
                        }.onEnded { _ in dragOrigin = nil })
                        .simultaneousGesture(MagnifyGesture().onChanged { value in
                            if zoomOrigin == nil { zoomOrigin = zoom }
                            zoom = min(3, max(1, (zoomOrigin ?? 1) * value.magnification))
                        }.onEnded { _ in zoomOrigin = nil })
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityElement(children: .ignore).accessibilityLabel("Account photo preview")
                    .accessibilityIdentifier("avatar.crop-preview")
                    .accessibilityHint("Use the zoom and positioning buttons below to adjust the crop.")
                    HStack(spacing: 24) {
                        Button { zoom = max(1, zoom - 0.1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                            .disabled(zoom <= 1).accessibilityLabel("Zoom out")
                        Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 60)
                        Button { zoom = min(3, zoom + 0.1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                            .disabled(zoom >= 3).accessibilityLabel("Zoom in")
                    }.buttonStyle(.glass).buttonBorderShape(.circle)
                    HStack(spacing: 0) {
                        positionButton("Move left", symbol: "arrow.left", x: -0.1, y: 0)
                        Divider().frame(height: 24)
                        positionButton("Move up", symbol: "arrow.up", x: 0, y: -0.1)
                        Divider().frame(height: 24)
                        positionButton("Move down", symbol: "arrow.down", x: 0, y: 0.1)
                        Divider().frame(height: 24)
                        positionButton("Move right", symbol: "arrow.right", x: 0.1, y: 0)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
                    Button("Reset") { zoom = 1; horizontal = 0; vertical = 0 }
                        .disabled(zoom == 1 && horizontal == 0 && vertical == 0)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                }
                .frame(maxWidth: 460)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo", action: save)
                        .disabled(account.isBusy)
                }
            }
        }
        .onChange(of: account.userID) { _, id in
            if id != selection.ownerID { dismiss() }
        }
    }

    private func clamp(_ value: Double) -> Double { min(1, max(-1, value)) }
    private func positionButton(_ title: String, symbol: String, x: Double, y: Double) -> some View {
        Button { horizontal = clamp(horizontal + x); vertical = clamp(vertical + y) } label: {
            Image(systemName: symbol).frame(width: 48, height: 44).contentShape(Rectangle())
        }.accessibilityLabel(title)
    }

    private func save() {
        guard account.userID == selection.ownerID else { dismiss(); return }
        do {
            let png = try AvatarImageService.crop(selection.image, zoom: zoom, horizontal: horizontal, vertical: vertical)
            usePhoto(png)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
