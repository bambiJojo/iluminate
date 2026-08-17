//
//  IlumionateApp.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

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
#endif

@main
struct IlumionateApp: App {

    /// Owned at the app root, not inside `ContentView`.
    ///
    /// Every analysis surface reads this through the environment, and some of
    /// them are reached through nested sheets. Injecting it from inside
    /// `ContentView` left those presentations without an ancestor that
    /// provided it, which trapped with "No Observable object of type
    /// AnalysisCenterModel found". The scene root is the only place that is
    /// unambiguously an ancestor of everything.
    @State private var analysisCenter = AnalysisCenterModel.live()

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    init() {
        // Opt-out, default-on: listening history powers the Home streak/momentum
        // indicator. Only sets the value for users who have never made an explicit
        // choice — an existing opt-out is preserved.
        UserDefaults.standard.register(defaults: [
            AppSettingsManager.Key.listeningHistoryEnabled: true
        ])
        UsageAnalytics.configure()
        #if os(macOS)
        BackgroundAnalysisScheduler.shared.register()
        #endif
        // Reclaim files left staged by a session that was killed during an
        // undo window. They are already gone from the library.
        PendingAudioDeletion.shared.sweepOrphans()
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView(navigationPresentation: .macSidebar)
                .frame(minWidth: 760, minHeight: 560)
                .environment(analysisCenter)
            #elseif targetEnvironment(macCatalyst)
            ContentView()
                .frame(minWidth: 760, minHeight: 560)
                .environment(analysisCenter)
            #else
            ContentView()
                .environment(analysisCenter)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1_100, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
        #elseif targetEnvironment(macCatalyst)
        .defaultSize(width: 1_100, height: 760)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            ProfileSettingsView()
                .frame(minWidth: 640, minHeight: 620)
        }
        #endif
    }
}
