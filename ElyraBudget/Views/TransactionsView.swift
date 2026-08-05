//
//  TransactionsView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
//


import SwiftUI

struct TransactionsView: View {
    var body: some View {
        ContentUnavailableView(
            "Noch keine Buchungen",
            systemImage: "list.bullet.rectangle",
            description: Text(
                "Deine Einnahmen und Ausgaben erscheinen hier."
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
    TransactionsView()
}
