//
//  ContentView.swift
//  LiveLearningCamera
//
//  Created by Elijah Arbee on 8/11/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView()
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
