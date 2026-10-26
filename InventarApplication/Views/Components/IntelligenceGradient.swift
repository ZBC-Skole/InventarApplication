//
//  IntelligenceGradient.swift
//  InventarApplication
//

import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    /// The purple–pink–orange gradient used to mark Apple Intelligence features.
    static var intelligenceGradient: LinearGradient {
        LinearGradient(
            colors: [.purple, .pink, .orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
