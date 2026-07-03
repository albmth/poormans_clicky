//
//  leanring_buddyApp.swift
//  leanring-buddy
//

import AppKit
import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private var tutorialPromptPanelManager: TutorialPromptPanelManager?
    private let clickyCursorFollowerWindowManager = ClickyCursorFollowerWindowManager()
    private let companionManager = CompanionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)
        tutorialPromptPanelManager = TutorialPromptPanelManager(companionManager: companionManager)
        companionManager.start()
        clickyCursorFollowerWindowManager.start()
        tutorialPromptPanelManager?.start()
        menuBarPanelManager?.showPanelOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clickyCursorFollowerWindowManager.stop()
        tutorialPromptPanelManager?.stop()
        companionManager.stop()
    }
}
