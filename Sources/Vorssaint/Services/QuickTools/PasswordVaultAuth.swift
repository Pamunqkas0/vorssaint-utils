// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import LocalAuthentication

enum PasswordVaultAuth {
    static var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func authenticate(reason: String, completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        // .deviceOwnerAuthentication prompts for Touch ID if enrolled, or Mac user passcode/password as fallback
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        completion(true, nil)
                    } else {
                        completion(false, authError?.localizedDescription ?? "Authentication failed")
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                completion(false, error?.localizedDescription ?? "Device authentication unavailable")
            }
        }
    }
}
