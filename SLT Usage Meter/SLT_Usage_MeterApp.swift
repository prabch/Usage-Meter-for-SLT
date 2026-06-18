//
//  SLT_Usage_MeterApp.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2024-06-30.
//

import SwiftUI

@main
struct SLT_Usage_MeterApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        #if os(iOS)
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                #if os(macOS)
                .frame(minWidth: 375, minHeight: 650)
                #endif
        }
    }
}
