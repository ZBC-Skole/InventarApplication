//
//  EquipmentDetailView.swift
//  InventarApplication
//

import AppKit
import SwiftData
import SwiftUI

/// Shows everything about the selected item (Krav 3).
struct EquipmentDetailView: View {
    let equipment: Equipment
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                hero
                    .listRowInsets(EdgeInsets())
            }

            Section("Oplysninger") {
                LabeledContent("Navn", value: equipment.name)
                LabeledContent("Serienummer") {
                    HStack(spacing: 6) {
                        Text(equipment.serialNumber)
                            .monospaced()
                            .textSelection(.enabled)
                        Button("Kopiér serienummer", systemImage: "doc.on.doc")
                        {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                equipment.serialNumber,
                                forType: .string
                            )
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Kopiér serienummer")
                    }
                }
                LabeledContent("Kategori") {
                    if let category = equipment.category {
                        Label(category.name, systemImage: category.symbolName)
                    } else {
                        Text("Ingen")
                    }
                }
                LabeledContent("Status") {
                    StatusBadge(status: equipment.status)
                }
            }

            if !equipment.notes.isEmpty {
                Section("Noter") {
                    Text(equipment.notes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                LabeledContent(
                    "Oprettet",
                    value: equipment.createdAt.formatted(
                        date: .long,
                        time: .shortened
                    )
                )
                LabeledContent(
                    "Sidst ændret",
                    value: equipment.updatedAt.formatted(
                        date: .long,
                        time: .shortened
                    )
                )
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup {
                Button("Rediger", systemImage: "pencil", action: onEdit)
                    .help("Rediger udstyr")
                Button(
                    "Slet",
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )
                .help("Slet udstyr")
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    equipment.status.color.opacity(0.22),
                    equipment.status.color.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            heroImage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(equipment.name)
                    .font(.title.bold())
                    .lineLimit(2)
                StatusBadge(status: equipment.status, isProminent: true)
            }
            .padding(20)
        }
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var heroImage: some View {
        if let data = equipment.displayImageData,
            let image = NSImage(data: data)
        {
            let isCutout =
                equipment.prefersCutout && equipment.cutoutData != nil
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: isCutout ? .fit : .fill)
                .padding(isCutout ? 32 : 0)
                .padding(.bottom, isCutout ? 48 : 0)
                .shadow(
                    color: .black.opacity(isCutout ? 0.25 : 0),
                    radius: 18,
                    y: 10
                )
                .clipped()
        } else {
            Image(systemName: equipment.placeholderSymbolName)
                .font(.system(size: 88, weight: .light))
                .foregroundStyle(equipment.status.color.opacity(0.6))
                .padding(.bottom, 48)
        }
    }
}

#Preview {
    let container = InventoryStore.makePreviewContainer()
    let item = try! container.mainContext.fetch(FetchDescriptor<Equipment>())
        .first!
    return NavigationStack {
        EquipmentDetailView(equipment: item, onEdit: {}, onDelete: {})
    }
    .modelContainer(container)
    .frame(width: 480, height: 760)
}
