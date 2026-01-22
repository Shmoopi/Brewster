//
//  StatusBarController.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Cocoa
import ServiceManagement
import UserNotifications
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shmoopi.Brewster", category: "StatusBarController")

class StatusBarController: NSObject, NSMenuDelegate {

    // MARK: Properties

    private var statusItem: NSStatusItem!
    private var updates: [String] = []
    private let homebrewManager = HomebrewManager()

    private var originalTexts: [NSMenuItem: String] = [:]
    private var alternateTexts: [NSMenuItem: String] = [:]
    private var menuObserver: CFRunLoopObserver?

    // Store reference to interval submenu item
    private weak var intervalSubmenuItem: NSMenuItem?

    // Concurrency guard
    private var isOperationInProgress = false

    // Notification settings
    private let notificationsEnabledKey = "notificationsEnabledKey"
    private var notificationsEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey)
        }
    }

    enum TimeIntervalOption: String, CaseIterable {
        case oneHour = "1h"
        case sixHours = "6h"
        case twelveHours = "12h"
        case oneDay = "1d"
        case sevenDays = "7d"

        var timeInterval: TimeInterval {
            switch self {
            case .oneHour:
                return 60 * 60
            case .sixHours:
                return 6 * 60 * 60
            case .twelveHours:
                return 12 * 60 * 60
            case .oneDay:
                return 24 * 60 * 60
            case .sevenDays:
                return 7 * 24 * 60 * 60
            }
        }
    }

    private var timer: Timer?
    private let selectedIntervalKey = "selectedIntervalKey"
    private var selectedInterval: TimeIntervalOption {
        get {
            if let savedValue = UserDefaults.standard.string(forKey: selectedIntervalKey),
               let interval = TimeIntervalOption(rawValue: savedValue) {
                return interval
            }
            return .oneDay // Default value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedIntervalKey)
        }
    }

    // MARK: Functions

    // Init
    override init() {
        super.init()

        logger.info("Brewster initializing")

        // Request notification permissions
        requestNotificationPermissions()

        // Setup the menu bar items
        setupMenuBarItem()

        // Check for brew updates
        checkForHomebrewUpdates()

        // Start timer
        startTimer()
    }

    // MARK: Notifications

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else {
                logger.info("Notification permissions granted: \(granted)")
            }
        }
    }

    private func sendUpdateNotification(count: Int) {
        guard notificationsEnabled, count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Homebrew Updates Available"
        content.body = count == 1 ? "1 package can be upgraded" : "\(count) packages can be upgraded"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Brewing..."

        let menu = NSMenu()
        menu.delegate = self  // Set the menu delegate
        statusItem.menu = menu

        // Add "Updating Homebrew..." menubaritem
        let updatingItem = NSMenuItem(title: "Updating Homebrew...", action: nil, keyEquivalent: "")
        menu.addItem(updatingItem)

        // Add the bottom submenu
        setupBottomMenu(menu)
    }

    private func setupBottomMenu(_ menu: NSMenu) {
        // Add a separator
        menu.addItem(NSMenuItem.separator())

        // Create the submenu
        let submenu = NSMenu()

        // Brewster version item
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let versionItem = NSMenuItem(title: "Brewster \(version)", action: nil, keyEquivalent: "")
        submenu.addItem(versionItem)

        // Add a separator
        submenu.addItem(NSMenuItem.separator())

        // Refresh item
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshUpdates), keyEquivalent: "r")
        refreshItem.target = self
        submenu.addItem(refreshItem)

        // Run in Terminal item
        let runInTerminalItem = NSMenuItem(title: "Run in Terminal", action: #selector(runInTerminal), keyEquivalent: "t")
        runInTerminalItem.target = self
        submenu.addItem(runInTerminalItem)

        // Add frequency submenu
        let intervalSubmenu = NSMenu()

        for intervalOption in TimeIntervalOption.allCases {
            let menuItem = NSMenuItem(title: intervalOption.rawValue, action: #selector(changeInterval(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = intervalOption
            menuItem.state = intervalOption == selectedInterval ? .on : .off
            intervalSubmenu.addItem(menuItem)
        }

        let intervalItem = NSMenuItem()
        intervalItem.title = "Update Frequency"
        intervalItem.submenu = intervalSubmenu
        submenu.addItem(intervalItem)

        // Store reference to avoid fragile string lookup later
        self.intervalSubmenuItem = intervalItem

        // Notifications toggle
        let notificationsItem = NSMenuItem(title: "Notifications", action: #selector(toggleNotifications(_:)), keyEquivalent: "")
        notificationsItem.target = self
        notificationsItem.state = notificationsEnabled ? .on : .off
        submenu.addItem(notificationsItem)

        // Start at login item
        let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "")
        startAtLoginItem.target = self
        startAtLoginItem.state = isLoginItemEnabled() ? .on : .off
        submenu.addItem(startAtLoginItem)

        // Add a separator
        submenu.addItem(NSMenuItem.separator())

        // Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        submenu.addItem(quitItem)

        // Add the submenu to the main menu
        let submenuItem = NSMenuItem()
        submenuItem.title = "Options"
        submenuItem.submenu = submenu
        menu.addItem(submenuItem)
    }

    private func clearAllMenuBarItems() {
        statusItem.menu?.removeAllItems()
        originalTexts.removeAll()
        alternateTexts.removeAll()
        intervalSubmenuItem = nil
    }

    @objc private func refreshUpdates() {
        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.debug("Refresh skipped - operation already in progress")
            return
        }

        clearAllMenuBarItems()
        setupMenuBarItem()
        checkForHomebrewUpdates()
    }

    private func checkForHomebrewUpdates() {
        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.debug("Update check skipped - operation already in progress")
            return
        }

        isOperationInProgress = true
        logger.info("Checking for Homebrew updates")

        DispatchQueue.global().async {
            let result = self.homebrewManager.getHomebrewUpdates()
            DispatchQueue.main.async {
                self.isOperationInProgress = false
                self.handleHomebrewUpdateResult(result)
            }
        }
    }

    private func handleHomebrewUpdateResult(_ result: Result<[String], HomebrewError>) {
        switch result {
        case .success(let updates):
            logger.info("Found \(updates.count) available updates")

            // Send notification if new updates are available
            let previousCount = self.updates.count
            if updates.count > previousCount {
                sendUpdateNotification(count: updates.count)
            }

            self.updateMenuBar(updates: updates)
        case .failure(let error):
            logger.error("Failed to check updates: \(error.localizedDescription)")
            self.showError(error: error)
        }
    }

    private func updateMenuBar(updates: [String]) {
        self.updates = updates

        guard let menu = statusItem.menu else {
            logger.error("Menu is nil, cannot update menu bar")
            return
        }

        // Check for updates
        if updates.isEmpty {

            // Set the menu bar icon
            statusItem.button?.title = "🍺"

            // Clear all menu items
            clearAllMenuBarItems()

            // Add noUpdates menubaritem
            let noUpdates = NSMenuItem(title: "All Up-To-Date!", action: nil, keyEquivalent: "")
            menu.addItem(noUpdates)

            // Re-add the bottom submenu
            setupBottomMenu(menu)

        } else {

            statusItem.button?.title = "↑\(updates.count)"
            clearAllMenuBarItems()

            let upgradeAllMenuItem = NSMenuItem(title: "Upgrade All", action: #selector(upgradeAllPackages(_:)), keyEquivalent: "u")
            upgradeAllMenuItem.target = self
            menu.addItem(upgradeAllMenuItem)

            // Separator
            menu.addItem(.separator())

            // Add all the updateable items
            for update in updates {

                // Get the first part of the update string before the first " (" - skipping if it doesn't have it
                guard let name = update.components(separatedBy: " (").first else {
                    continue
                }

                let menuItem = NSMenuItem(title: name, action: #selector(updateHomebrewPackage(_:)), keyEquivalent: "")
                menuItem.representedObject = name
                menuItem.target = self
                originalTexts[menuItem] = name
                alternateTexts[menuItem] = update
                menu.addItem(menuItem)
            }

            // Re-add the bottom submenu
            setupBottomMenu(menu)
        }
    }

    @objc private func upgradeAllPackages(_ sender: NSMenuItem) {
        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.debug("Upgrade all skipped - operation already in progress")
            return
        }

        isOperationInProgress = true
        logger.info("Upgrading all packages")

        // Set the title to brewing
        statusItem.button?.title = "Brewing..."

        // Remove all items
        clearAllMenuBarItems()

        // Add an "Upgrading All..." item
        let upgradingAllMenuItem = NSMenuItem(title: "Upgrading All...", action: nil, keyEquivalent: "")
        statusItem.menu?.addItem(upgradingAllMenuItem)

        // Separator
        statusItem.menu?.addItem(.separator())

        // Re-add the bottom submenu
        if let menu = statusItem.menu {
            setupBottomMenu(menu)
        }

        // Upgrade all packages
        DispatchQueue.global().async {
            let result = self.homebrewManager.upgradeAllPackages()
            DispatchQueue.main.async {
                self.isOperationInProgress = false
                self.handlePackageUpdateResult(result)
            }
        }
    }

    @objc private func updateHomebrewPackage(_ sender: NSMenuItem) {
        guard let package = sender.representedObject as? String else { return }

        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.debug("Package upgrade skipped - operation already in progress")
            return
        }

        isOperationInProgress = true
        logger.info("Upgrading package: \(package)")

        // Set the title to brewing
        statusItem.button?.title = "Brewing..."

        // Set the menuitem action to disabled - don't allow running update twice
        sender.action = nil

        // Upgrade the package
        DispatchQueue.global().async {
            let result = self.homebrewManager.upgradePackage(package: package)
            DispatchQueue.main.async {
                self.isOperationInProgress = false
                self.handlePackageUpdateResult(result)
            }
        }
    }

    private func handlePackageUpdateResult(_ result: Result<Void, HomebrewError>) {
        switch result {
        case .success:
            logger.info("Package upgrade completed successfully")
            self.checkForHomebrewUpdates()
        case .failure(let error):
            logger.error("Package upgrade failed: \(error.localizedDescription)")
            self.showError(error: error)
        }
    }

    @objc private func runInTerminal() {
        logger.debug("Opening Terminal with brew outdated")
        let script = """
            tell application "Terminal"
                activate
                do script "brew outdated"
            end tell
            """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        do {
            try task.run()
        } catch {
            logger.error("Failed to run Terminal script: \(error.localizedDescription)")
        }
    }

    @objc private func quitApp() {
        logger.info("Quitting Brewster")
        NSApplication.shared.terminate(self)
    }

    private func showError(error: HomebrewError) {
        statusItem.button?.title = "Brew Error"
        clearAllMenuBarItems()

        let menuItem = NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: "")
        statusItem.menu?.addItem(menuItem)

        // Show submenu
        if let menu = statusItem.menu {
            setupBottomMenu(menu)
        }
    }

    // MARK: Notifications Toggle

    @objc private func toggleNotifications(_ sender: NSMenuItem) {
        notificationsEnabled = !notificationsEnabled
        sender.state = notificationsEnabled ? .on : .off
        logger.info("Notifications \(self.notificationsEnabled ? "enabled" : "disabled")")
    }

    // MARK: Start At Login

    @objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
        let shouldEnable = sender.state == .off
        if shouldEnable {
            enableLoginItem()
        } else {
            disableLoginItem()
        }
        sender.state = shouldEnable ? .on : .off
    }

    private func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    private func enableLoginItem() {
        do {
            try SMAppService.mainApp.register()
            logger.info("Login item enabled")
        } catch {
            logger.error("Error registering for startup: \(error.localizedDescription)")
        }
    }

    private func disableLoginItem() {
        do {
            try SMAppService.mainApp.unregister()
            logger.info("Login item disabled")
        } catch {
            logger.error("Error unregistering for startup: \(error.localizedDescription)")
        }
    }

    // MARK: Menu Items to show when option key held

    private func hiddenOptionKeyMenu() {
        let isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)
        for menuItem in statusItem.menu?.items ?? [] {
            if isOptionKeyPressed {
                if let alternateText = alternateTexts[menuItem] {
                    menuItem.title = alternateText
                }
            } else {
                if let originalText = originalTexts[menuItem] {
                    menuItem.title = originalText
                }
            }
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        hiddenOptionKeyMenu()

        if menuObserver == nil {
            menuObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
                self?.hiddenOptionKeyMenu()
            }

            if let observer = menuObserver {
                CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, .commonModes)
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if let observer = menuObserver {
            CFRunLoopObserverInvalidate(observer)
            menuObserver = nil
        }
    }

    // MARK: Checking Frequency

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: selectedInterval.timeInterval, target: self, selector: #selector(refreshUpdates), userInfo: nil, repeats: true)
        logger.debug("Timer started with interval: \(self.selectedInterval.rawValue)")
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard let selectedOption = sender.representedObject as? TimeIntervalOption else { return }
        selectedInterval = selectedOption
        startTimer()
        updateIntervalSubmenuState()
        logger.info("Update interval changed to: \(selectedOption.rawValue)")
    }

    private func updateIntervalSubmenuState() {
        // Use stored reference instead of fragile string lookup
        guard let intervalSubmenu = intervalSubmenuItem?.submenu else { return }
        for item in intervalSubmenu.items {
            if let intervalOption = item.representedObject as? TimeIntervalOption {
                item.state = intervalOption == selectedInterval ? .on : .off
            }
        }
    }
}
