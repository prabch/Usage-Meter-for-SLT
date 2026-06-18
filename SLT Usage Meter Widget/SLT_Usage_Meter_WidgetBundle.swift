//
//  SLT_Usage_Meter_WidgetBundle.swift
//  SLT Usage Meter Widget
//
//  Created by Prabhashwara on 28-12-2025.
//

import WidgetKit
import SwiftUI

@main
struct AppWidgetLauncher {
    static func main() {
        if #available(iOS 17.0, macOS 14.0, *) {
            iOS17Bundle.main()
        } else {
            iOS15Bundle.main()
        }
    }
}

struct iOS17Bundle: WidgetBundle {
    var body: some Widget {
        SLT_Usage_Meter_Widget()
    }
}

struct iOS15Bundle: WidgetBundle {
    var body: some Widget {
        SLT_Usage_Meter_Widget()
        SLT_Usage_Meter_Widget_V2()
    }
}
