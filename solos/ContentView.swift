//
//  ContentView.swift
//  solos
//
//  Created by Pranavi Kuntrapakam on 25/06/26.
//

import SwiftUI

struct ContentView: View {
    @State private var model = AppViewModel()

    var body: some View {
        GlassesConnectView(model: model)
    }
}

#Preview {
    ContentView()
}
