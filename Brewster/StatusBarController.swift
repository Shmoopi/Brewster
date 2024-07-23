//
//  StatusBarController.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Cocoa
import ServiceManagement

class StatusBarController: NSObject, NSMenuDelegate {
    
    // MARK: Properties

    private var statusItem: NSStatusItem!
    private var updates: [String] = []
    private let homebrewManager = HomebrewManager()
    
    private var originalTexts: [NSMenuItem: String] = [:]
    private var alternateTexts: [NSMenuItem: String] = [:]
    private var menuObserver: CFRunLoopObserver?
    
    enum TimeIntervalOption: String, CaseIterable {
        case sixHours = "1h"
        case twelveHours = "12h"
        case oneDay = "1d"
        case twoDays = "2d"
        case sevenDays = "7d"

        var timeInterval: TimeInterval {
            switch self {
            case .sixHours:
                return 60 * 60
            case .twelveHours:
                return 12 * 60 * 60
            case .oneDay:
                return 24 * 60 * 60
            case .twoDays:
                return 48 * 60 * 60
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
        
        // Setup the menu bar items
        setupMenuBarItem()
        
        // Check for brew updates
        checkForHomebrewUpdates()
        
        // Start timer
        startTimer()
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
        
        let intervalSubmenuItem = NSMenuItem()
        intervalSubmenuItem.title = "Update Frequency"
        intervalSubmenuItem.submenu = intervalSubmenu
        submenu.addItem(intervalSubmenuItem)
        
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
    }
    
    @objc private func refreshUpdates() {
        clearAllMenuBarItems()
        setupMenuBarItem()
        checkForHomebrewUpdates()
    }
    
    private func checkForHomebrewUpdates() {
        DispatchQueue.global().async {
            let result = self.homebrewManager.getHomebrewUpdates()
            DispatchQueue.main.async {
                self.handleHomebrewUpdateResult(result)
            }
        }
    }
    
    private func handleHomebrewUpdateResult(_ result: Result<[String], HomebrewError>) {
        switch result {
        case .success(let updates):
            self.updateMenuBar(updates: updates)
        case .failure(let error):
            self.showError(error: error)
        }
    }
    
    private func updateMenuBar(updates: [String]) {
        self.updates = updates
        
        // Check for updates
        if updates.isEmpty {
            
            // Set the menu bar icon
            statusItem.button?.title = "🍺"
            
            // Clear all menu items
            clearAllMenuBarItems()
            
            // Add noUpdates menubaritem
            let noUpdates = NSMenuItem(title: "All Up-To-Date!", action: nil, keyEquivalent: "")
            statusItem.menu!.addItem(noUpdates)
            
            // Re-add the bottom submenu
            setupBottomMenu(statusItem.menu!)
            
        } else {
            
            statusItem.button?.title = "↑\(updates.count)"
            clearAllMenuBarItems()
            
            let upgradeAllMenuItem = NSMenuItem(title: "Upgrade All", action: #selector(upgradeAllPackages(_:)), keyEquivalent: "u")
            upgradeAllMenuItem.target = self
            statusItem.menu?.addItem(upgradeAllMenuItem)
            
            // Separator
            statusItem.menu?.addItem(.separator())
            
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
                statusItem.menu?.addItem(menuItem)
            }
            
            // Re-add the bottom submenu
            setupBottomMenu(statusItem.menu!)
        }
    }
    
    @objc private func upgradeAllPackages(_ sender: NSMenuItem) {
        
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
        setupBottomMenu(statusItem.menu!)
        
        // Upgrade all packages
        DispatchQueue.global().async {
            let result = self.homebrewManager.upgradeAllPackages()
            DispatchQueue.main.async {
                self.handlePackageUpdateResult(result)
            }
        }
    }
    
    @objc private func updateHomebrewPackage(_ sender: NSMenuItem) {
        guard let package = sender.representedObject as? String else { return }
        
        // Set the title to brewing
        statusItem.button?.title = "Brewing..."
        
        // Set the menuitem action to disabled - don't allow running update twice
        sender.action = nil
        
        // Upgrade the package
        DispatchQueue.global().async {
            let result = self.homebrewManager.upgradePackage(package: package)
            DispatchQueue.main.async {
                self.handlePackageUpdateResult(result)
            }
        }
    }
    
    private func handlePackageUpdateResult(_ result: Result<Void, HomebrewError>) {
        switch result {
        case .success:
            self.checkForHomebrewUpdates()
        case .failure(let error):
            self.showError(error: error)
        }
    }
    
    @objc private func runInTerminal() {
        let script = """
            tell application "Terminal"
                activate
                do script "brew outdated"
            end tell
            """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        task.launch()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    private func showError(error: HomebrewError) {
        statusItem.button?.title = "Brew Error"
        clearAllMenuBarItems()
        
        let menuItem = NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: "")
        statusItem.menu?.addItem(menuItem)
        
        // Show submenu
        setupBottomMenu(statusItem.menu!)
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
        if SMAppService.mainApp.status == .enabled {
            return true
        } else {
            return false
        }
    }
    
    private func enableLoginItem() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Error registering for startup: \(error)")
        }
    }
    
    private func disableLoginItem() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("Error unregistering for startup: \(error)")
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
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard let selectedOption = sender.representedObject as? TimeIntervalOption else { return }
        selectedInterval = selectedOption
        startTimer()
        updateIntervalSubmenuState()
    }

    private func updateIntervalSubmenuState() {
        guard let intervalSubmenu = statusItem.menu?.item(withTitle: "Update Frequency")?.submenu else { return }
        for item in intervalSubmenu.items {
            if let intervalOption = item.representedObject as? TimeIntervalOption {
                item.state = intervalOption == selectedInterval ? .on : .off
            }
        }
    }


}
