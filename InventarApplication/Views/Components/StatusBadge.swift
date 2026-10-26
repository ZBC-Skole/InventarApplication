//
//  StatusBadge.swift
//  InventarApplication
//

import SwiftUI

extension EquipmentStatus {
    var color: Color {
        switch self {
        case .available: .green
        case .inUse: .blue
        case .inRepair: .orange
        case .retired: .gray
        }
    }
}

/// A coloured capsule showing an equipment status.
struct StatusBadge: View {
    let status: EquipmentStatus
    var isProminent = false

    /// `.increased` inside a selected table row, where the tint would vanish against the highlight.
    @Environment(\.backgroundProminence) private var backgroundProminence

    private var tint: Color {
        backgroundProminence == .increased ? .white : status.color
    }

    var body: some View {
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.symbolName)
        }
        .font(
            isProminent ? .callout.weight(.semibold) : .caption.weight(.medium)
        )
        .foregroundStyle(tint)
        .padding(.horizontal, isProminent ? 12 : 8)
        .padding(.vertical, isProminent ? 6 : 3)
        .background {
            if !isProminent {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .glassEffect(
            isProminent ? .regular.tint(status.color.opacity(0.25)) : .identity,
            in: .capsule
        )
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(EquipmentStatus.allCases) { status in
            HStack {
                StatusBadge(status: status)
                StatusBadge(status: status, isProminent: true)
            }
        }
    }
    .padding()
}
