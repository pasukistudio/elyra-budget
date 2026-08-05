//
//  SavingsView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
//

import SwiftUI

struct SavingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Noch keine Sparziele",
            systemImage: "banknote",
            description: Text(
                "Deine Sparziele erscheinen später hier."
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
    SavingsView()
}
