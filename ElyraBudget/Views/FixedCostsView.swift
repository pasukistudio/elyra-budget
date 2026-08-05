//
//  FixedCostsView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
//


import SwiftUI

struct FixedCostsView: View {
    var body: some View {
        ContentUnavailableView(
            "Noch keine Fixkosten",
            systemImage: "calendar.badge.clock",
            description: Text(
                "Regelmäßige Ausgaben erscheinen später hier."
            )
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .center
        )
    }
}

#Preview {
    FixedCostsView()
}
