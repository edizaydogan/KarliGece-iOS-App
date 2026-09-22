//
//  InterestCalculatorApp.swift
//  InterestCalculator
//
//  Created by Ediz Aydoğan on 6.09.2026.
//

import SwiftUI

@main
struct InterestCalculatorApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(state)
        }
    }
}
