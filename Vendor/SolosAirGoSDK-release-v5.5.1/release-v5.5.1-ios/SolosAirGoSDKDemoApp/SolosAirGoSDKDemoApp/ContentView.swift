//
//  ContentView.swift
//  SolosAirGoSDKDemoApp
//
//  Created by ChunTung Chow on 7/2/2025.
//

import SwiftUI
import SolosAirGoSDK

struct ContentView: View {
    @State private var scanTabNavigationPath = NavigationPath()
    @State private var directConnectTabNavigationPath = NavigationPath()
    @State private var soloChefDemoNavigationPath = NavigationPath()
    @State private var tabSelection = 2
    
    var body: some View {
        TabView(selection: $tabSelection) {
            Tab("SoloChef Demo", systemImage: "frying.pan.fill", value: 2) {
                NavigationStack(path: $soloChefDemoNavigationPath) {
                    SoloChefDemoView()
                }
            }

            Tab("Scan", systemImage: "magnifyingglass", value: 0) {
                NavigationStack(path: $scanTabNavigationPath) {
                    ScanTab(navigationPath: $scanTabNavigationPath)
                }
            }
            
            Tab("Direct Connection", systemImage: "number", value: 1) {
                NavigationStack(path: $directConnectTabNavigationPath) {
                    DirectConnectionTab(navigationPath: $directConnectTabNavigationPath)
                }
            }
        }
        .onAppear {
            SolosSdkLibrary.configure()
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
