//
//  IlumionateApp.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundAnalysisScheduler.shared.register()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        BackgroundAnalysisScheduler.shared.resumeWhenForegrounded()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            let pending = await AnalysisProgressStore.shared.allPending()
            if !pending.isEmpty {
                BackgroundAnalysisScheduler.shared.scheduleDeferredProcessing()
            }
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct IlumionateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Opt-out, default-on: listening history powers the Home streak/momentum
        // indicator. Only sets the value for users who have never made an explicit
        // choice — an existing opt-out is preserved.
        UserDefaults.standard.register(defaults: [
            AppSettingsManager.Key.listeningHistoryEnabled: true
        ])
        UsageAnalytics.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
