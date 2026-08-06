//
//  KeyboardDismissModifier.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//


//
//  KeyboardDismissModifier.swift
//  ElyraBudget
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

extension View {
    /// Schließt die Tastatur, wenn außerhalb eines Textfeldes
    /// oder TextEditors getippt wird.
    func dismissKeyboardOnTap() -> some View {
        modifier(
            KeyboardDismissModifier()
        )
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(
        content: Content
    ) -> some View {
        #if os(iOS)
        content.background {
            KeyboardDismissGestureInstaller()
                .frame(
                    width: 0,
                    height: 0
                )
        }
        #else
        content
        #endif
    }
}

#if os(iOS)

private struct KeyboardDismissGestureInstaller:
    UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(
        context: Context
    ) -> KeyboardDismissInstallerView {
        let view = KeyboardDismissInstallerView()

        view.onWindowAvailable = { window in
            context.coordinator.installGesture(
                in: window
            )
        }

        return view
    }

    func updateUIView(
        _ uiView: KeyboardDismissInstallerView,
        context: Context
    ) {
        if let window = uiView.window {
            context.coordinator.installGesture(
                in: window
            )
        }
    }

    static func dismantleUIView(
        _ uiView: KeyboardDismissInstallerView,
        coordinator: Coordinator
    ) {
        coordinator.removeGesture()
    }

    final class Coordinator:
        NSObject,
        UIGestureRecognizerDelegate {

        private weak var installedWindow: UIWindow?
        private weak var tapGesture:
            UITapGestureRecognizer?

        func installGesture(
            in window: UIWindow
        ) {
            guard installedWindow !== window else {
                return
            }

            removeGesture()

            let gesture =
                UITapGestureRecognizer(
                    target: self,
                    action:
                        #selector(
                            dismissKeyboard
                        )
                )

            gesture.cancelsTouchesInView = false
            gesture.delegate = self

            window.addGestureRecognizer(
                gesture
            )

            installedWindow = window
            tapGesture = gesture
        }

        func removeGesture() {
            guard
                let installedWindow,
                let tapGesture
            else {
                return
            }

            installedWindow
                .removeGestureRecognizer(
                    tapGesture
                )

            self.installedWindow = nil
            self.tapGesture = nil
        }

        @objc
        private func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(
                    UIResponder
                        .resignFirstResponder
                ),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer:
                UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var touchedView:
                UIView? = touch.view

            while let currentView =
                touchedView {
                if currentView
                    is UITextField {
                    return false
                }

                if currentView
                    is UITextView {
                    return false
                }

                touchedView =
                    currentView.superview
            }

            return true
        }
    }
}

private final class KeyboardDismissInstallerView:
    UIView {

    var onWindowAvailable:
        ((UIWindow) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard let window else {
            return
        }

        onWindowAvailable?(window)
    }
}

#endif