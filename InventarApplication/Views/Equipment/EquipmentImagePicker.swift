//
//  EquipmentImagePicker.swift
//  InventarApplication
//

import AppKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Lets the user add a photo by dropping, pasting, choosing a file, picking
/// from Photos or taking one with Continuity Camera. The subject is cut out
/// automatically with on-device Vision.
struct EquipmentImagePicker: View {
    @Binding var draft: EquipmentDraft
    /// Called with the stored photo once a new image has been imported and processed.
    var onImageImported: (Data) -> Void = { _ in }

    @State private var isProcessing = false
    @State private var isImportingFile = false
    @State private var isDropTargeted = false
    @State private var photosItem: PhotosPickerItem?
    @State private var errorMessage: LocalizedStringResource?

    var body: some View {
        VStack(spacing: 12) {
            preview
            controls
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            importFile(at: url)
        }
        .onChange(of: photosItem) { _, item in
            guard let item else { return }
            photosItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    errorMessage = "Billedet kunne ikke hentes fra Fotos."
                    return
                }
                await importImage(data)
            }
        }
        .onChange(of: draft.prefersCutout) {
            Task { await refreshThumbnail() }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quinary)

            if let data = draft.displayImageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .shadow(color: .black.opacity(isShowingCutout ? 0.2 : 0), radius: 12, y: 6)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tint)
                    Text("Træk et billede hertil")
                        .font(.headline)
                    Text("…eller indsæt, vælg en fil, et foto, eller tag et billede med din iPhone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }

            if isProcessing {
                ProgressView("Fjerner baggrund…")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(in: .rect(cornerRadius: 14))
            }
        }
        .frame(height: 240)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 1, dash: [6, 4])
                )
                .opacity(draft.photoData == nil || isDropTargeted ? 1 : 0)
        }
        .animation(.smooth, value: isDropTargeted)
        .animation(.smooth, value: isProcessing)
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            importImage(from: providers)
        }
        .onPasteCommand(of: [.image]) { providers in
            _ = importImage(from: providers)
        }
        .importsItemProviders([.image]) { providers in
            importImage(from: providers)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        GlassEffectContainer {
            HStack {
                Button("Vælg fil…", systemImage: "folder") {
                    isImportingFile = true
                }
                PhotosPicker(selection: $photosItem, matching: .images) {
                    Label("Fotos", systemImage: "photo.on.rectangle")
                }

                Spacer()

                if draft.photoData != nil {
                    Toggle(isOn: $draft.prefersCutout) {
                        Label("Fjern baggrund", systemImage: "person.and.background.dotted")
                    }
                    .toggleStyle(.button)
                    .disabled(draft.cutoutData == nil)
                    .help(
                        draft.cutoutData == nil
                            ? "Der blev ikke fundet et tydeligt motiv i billedet."
                            : "Vis motivet uden baggrund."
                    )

                    Button("Fjern billede", systemImage: "trash", role: .destructive) {
                        draft.removeImage()
                    }
                    .labelStyle(.iconOnly)
                    .help("Fjern billede")
                }
            }
            .buttonStyle(.glass)
            .disabled(isProcessing)
        }
    }

    private var isShowingCutout: Bool {
        draft.prefersCutout && draft.cutoutData != nil
    }

    // MARK: - Importing

    private func importFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Filen kunne ikke åbnes."
            return
        }
        Task { await importImage(data) }
    }

    /// Loads the first image from drag and drop, paste or Continuity Camera.
    private func importImage(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else { return false }

        Task {
            do {
                let data = try await provider.loadImageData()
                await importImage(data)
            } catch {
                errorMessage = "Billedet kunne ikke indlæses."
            }
        }
        return true
    }

    private func importImage(_ data: Data) async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let image = try await ImageProcessor.process(data)
            draft.setImage(image)
            onImageImported(image.photo)
        } catch {
            errorMessage = "Billedet kunne ikke indlæses."
        }
    }

    private func refreshThumbnail() async {
        guard let data = draft.displayImageData else { return }
        draft.thumbnailData = try? await ImageProcessor.thumbnail(from: data)
    }
}

extension NSItemProvider {
    fileprivate func loadImageData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(for: .image) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }
}
