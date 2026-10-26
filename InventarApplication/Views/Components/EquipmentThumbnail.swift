//
//  EquipmentThumbnail.swift
//  InventarApplication
//

import AppKit
import SwiftUI

/// A small square image for table rows, falling back to the category symbol.
struct EquipmentThumbnail: View {
    let imageData: Data?
    let symbolName: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quinary, in: .rect(cornerRadius: size * 0.25))
            }
        }
        .frame(width: size, height: size)
    }
}

extension Equipment {
    /// The SF Symbol shown when the item has no photo.
    var placeholderSymbolName: String {
        category?.symbolName ?? "shippingbox.fill"
    }
}
