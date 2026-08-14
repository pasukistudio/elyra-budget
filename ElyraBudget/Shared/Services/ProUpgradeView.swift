import Foundation
import StoreKit
import SwiftUI

private enum AppLegalLinks {
    static let privacyPolicy = URL(string: "https://pasukistudio.de/datenschutz/")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProAccessManager.self) private var proAccess

    let feature: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    benefits
                    platformNote
                    planSelection
                    purchaseAction
                }
                .padding(24)
            }
            .navigationTitle("Elyra Budget Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task { await proAccess.loadProduct() }
            .alert(
                "Kauf nicht möglich",
                isPresented: Binding(
                    get: { proAccess.purchaseError != nil },
                    set: { if !$0 { proAccess.purchaseError = nil } }
                )
            ) {
                Button("OK") { proAccess.purchaseError = nil }
            } message: {
                Text(proAccess.purchaseError ?? "")
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)

            Text("Mehr Überblick. Mehr Ruhe.")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("\(feature) ist in Elyra Budget Pro enthalten.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefit("Detaillierte Prognosen", systemImage: "chart.line.uptrend.xyaxis")
            benefit("CSV- und PDF-Export", systemImage: "doc.richtext")
            benefit("CSV-Import", systemImage: "square.and.arrow.down")
            benefit("Face ID-/Touch-ID-Sperre", systemImage: "faceid")
            benefit("Statistiken und Monatsberichte", systemImage: "chart.xyaxis.line")
            benefit("Belege an Buchungen", systemImage: "paperclip")
            benefit("Wiederkehrende Buchungen erkennen", systemImage: "arrow.triangle.2.circlepath")
            benefit("Geteilte Budgetbereiche", systemImage: "person.2.badge.plus")
            benefit("Eigene Akzentfarben", systemImage: "paintpalette.fill")
            benefit("Mehr Kontrolle über deine Planung", systemImage: "slider.horizontal.3")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var purchaseAction: some View {
        VStack(spacing: 10) {
            if proAccess.hasPro {
                Label("Pro ist bereits freigeschaltet", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if let product = proAccess.selectedProduct {
                Button {
                    Task { await proAccess.purchase(plan: proAccess.selectedPlan) }
                } label: {
                    Text("Pro kaufen – \(product.displayPrice)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if proAccess.isLoadingProduct {
                ProgressView("Pro-Angebot wird geladen …")
            } else {
                Label(
                    "Das Pro-Angebot ist noch nicht im App Store konfiguriert.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Button {
                Task { await proAccess.restorePurchases() }
            } label: {
                if proAccess.isRestoringPurchases {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Käufe wiederherstellen")
                }
            }
            .buttonStyle(.borderless)
            .disabled(proAccess.isRestoringPurchases)

            Text("Du kannst Pro später jederzeit in deinen Apple‑Account‑Einstellungen verwalten.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(subscriptionTerms)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Datenschutz", destination: AppLegalLinks.privacyPolicy)
                Link("Nutzungsbedingungen (EULA)", destination: AppLegalLinks.termsOfUse)
            }
            .font(.footnote)
        }
    }

    private var planSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wähle dein Pro-Modell")
                .font(.headline)

            ForEach(ProProductPlan.allCases) { plan in
                Button {
                    proAccess.selectedPlan = plan
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: proAccess.selectedPlan == plan
                              ? "checkmark.circle.fill"
                              : "circle")
                            .foregroundStyle(proAccess.selectedPlan == plan ? Color.accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.title)
                                .font(.headline)
                            Text(plan.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let product = proAccess.products[plan.productID] {
                            Text(product.displayPrice)
                                .font(.headline)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(
                    proAccess.selectedPlan == plan
                        ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subscriptionTerms: String {
        switch proAccess.selectedPlan {
        case .monthly, .yearly:
            "Das ausgewählte Abo verlängert sich automatisch, sofern es nicht mindestens 24 Stunden vor Ablauf gekündigt wird. Verwaltung und Kündigung erfolgen in den Apple‑Account‑Einstellungen."
        case .lifetime:
            "Für immer ist ein einmaliger Kauf ohne automatische Verlängerung."
        }
    }

    private var platformNote: some View {
        Label {
            Text("Elyra Budget startet mit iOS. Eine optimierte iPadOS-Version und die Mac-App folgen nach einer eigenen Testphase. Die Mac-App kann zunächst 7 Tage kostenlos getestet werden und benötigt danach Pro.")
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func benefit(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

#if os(macOS)
/// Vollbild-Hinweis für die macOS-App nach Ablauf des kostenlosen Testzeitraums.
struct MacProRequiredView: View {
    @Environment(ProAccessManager.self) private var proAccess
    @State private var showingUpgrade = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Elyra Budget Pro erforderlich")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Deine kostenlose 7-Tage-Testphase auf dem Mac ist abgelaufen. Kaufe Pro, um deine Budgets, Buchungen und alle Pro-Funktionen weiter auf dem Mac zu nutzen.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            Button("Elyra Budget Pro freischalten") {
                showingUpgrade = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                Task { await proAccess.restorePurchases() }
            } label: {
                if proAccess.isRestoringPurchases {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Käufe wiederherstellen")
                }
            }
            .buttonStyle(.borderless)
            .disabled(proAccess.isRestoringPurchases)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .sheet(isPresented: $showingUpgrade) {
            ProUpgradeView(feature: "die Nutzung der Mac-App")
        }
        .alert(
            "Kauf nicht möglich",
            isPresented: Binding(
                get: { proAccess.purchaseError != nil },
                set: { if !$0 { proAccess.purchaseError = nil } }
            )
        ) {
            Button("OK") { proAccess.purchaseError = nil }
        } message: {
            Text(proAccess.purchaseError ?? "")
        }
    }
}
#endif
