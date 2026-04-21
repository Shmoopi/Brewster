//
//  HomeBrewManager.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shmoopi.Brewster", category: "HomebrewManager")

enum HomebrewError: Error, LocalizedError {
    case commandFailed(String)
    case homebrewNotFound
    case timeout
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .homebrewNotFound:
            return "Homebrew not found on this system."
        case .commandFailed(let message):
            return message
        case .timeout:
            return "Homebrew command timed out."
        case .userCancelled:
            return "Operation cancelled by user."
        }
    }
}

// MARK: - Protocol for testability

protocol HomebrewExecutable {
    func runCommand(arguments: [String], timeout: TimeInterval) -> Result<String, HomebrewError>
    func getHomebrewUpdates(runUpdateFirst: Bool) -> Result<[String], HomebrewError>
    func upgradePackage(package: String) -> Result<Void, HomebrewError>
    func upgradeAllPackages() -> Result<Void, HomebrewError>
    func installPackage(package: String) -> Result<Void, HomebrewError>
}

// Default timeout values
private let defaultCommandTimeout: TimeInterval = 120 // 2 minutes for most commands
private let updateCommandTimeout: TimeInterval = 300 // 5 minutes for brew update
private let upgradeCommandTimeout: TimeInterval = 600 // 10 minutes for upgrades

// UserDefaults keys
private let cachedBrewPathKey = "cachedBrewPath"
private let runUpdateFirstKey = "runUpdateFirstKey"

class HomebrewManager: HomebrewExecutable {

    private var brewPath: String?

    // User preference: run brew update before checking outdated
    var runUpdateFirst: Bool {
        get {
            return UserDefaults.standard.bool(forKey: runUpdateFirstKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: runUpdateFirstKey)
        }
    }

    init() {
        // Try to load cached path first
        if let cachedPath = UserDefaults.standard.string(forKey: cachedBrewPathKey),
           FileManager.default.fileExists(atPath: cachedPath) {
            logger.debug("Using cached brew path: \(cachedPath)")
            self.brewPath = cachedPath
        } else {
            // Find and cache the brew path
            self.brewPath = findHomebrewPath()
            if let path = self.brewPath {
                UserDefaults.standard.set(path, forKey: cachedBrewPathKey)
                logger.info("Cached brew path: \(path)")
            }
        }
    }

    private func findHomebrewPath() -> String? {
        let potentialPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for path in potentialPaths {
            if FileManager.default.fileExists(atPath: path) {
                logger.debug("Found Homebrew at: \(path)")
                return path
            }
        }

        // Try to find brew in the PATH
        logger.debug("Searching for Homebrew in PATH")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "brew"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if let output = try? pipe.fileHandleForReading.readToEnd(), process.terminationStatus == 0 {
                let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty {
                    logger.debug("Found Homebrew via which: \(path)")
                    return path
                }
            }
        } catch {
            logger.error("Error finding Homebrew path: \(error.localizedDescription)")
        }

        logger.warning("Homebrew not found")
        return nil
    }

    func runCommand(arguments: [String], timeout: TimeInterval = defaultCommandTimeout) -> Result<String, HomebrewError> {
        guard let brewPath = brewPath else {
            return .failure(.homebrewNotFound)
        }

        logger.info("Running brew \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["NONINTERACTIVE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment

        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Create a dispatch group for timeout handling
        let group = DispatchGroup()
        var didTimeout = false
        var processOutput: Data?
        var processError: Error?
        var exitStatus: Int32 = -1

        group.enter()

        DispatchQueue.global().async {
            do {
                try process.run()

                // Set up timeout
                let timeoutWorkItem = DispatchWorkItem {
                    if process.isRunning {
                        logger.warning("Command timed out after \(timeout) seconds, terminating")
                        didTimeout = true
                        process.terminate()
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                process.waitUntilExit()
                timeoutWorkItem.cancel()

                exitStatus = process.terminationStatus
                processOutput = try? pipe.fileHandleForReading.readToEnd()
            } catch {
                processError = error
            }
            group.leave()
        }

        // Wait for process to complete
        group.wait()

        if didTimeout {
            return .failure(.timeout)
        }

        if let error = processError {
            logger.error("Command failed with error: \(error.localizedDescription)")
            return .failure(.commandFailed(error.localizedDescription))
        }

        if exitStatus == 0 {
            let output = processOutput.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            logger.debug("Command completed successfully")
            return .success(output)
        } else {
            let errorOutput = processOutput.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            logger.error("Command failed with exit code \(exitStatus): \(errorOutput)")
            return .failure(.commandFailed(errorOutput))
        }
    }

    // MARK: - Interactive Command Execution

    /// Path to the sudo askpass helper script
    private lazy var askpassScriptPath: String? = {
        return createAskpassHelper()
    }()

    /// Creates a temporary askpass helper script that shows a macOS password dialog.
    /// sudo will invoke this script when it needs a password and no terminal is available.
    private func createAskpassHelper() -> String? {
        let scriptContent = """
        #!/bin/bash
        /usr/bin/osascript -e 'Tell application "System Events" to display dialog "Homebrew requires administrator privileges to continue." default answer "" with hidden answer with title "Brewster - Password Required"' -e 'text returned of result'
        """

        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("brewster_askpass.sh").path

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            // Make executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            logger.debug("Created askpass helper at: \(scriptPath)")
            return scriptPath
        } catch {
            logger.error("Failed to create askpass helper: \(error.localizedDescription)")
            return nil
        }
    }

    /// Patterns that indicate Homebrew is waiting for user input
    private static let inputPromptPatterns: [String] = [
        "Password:",
        "password:",
        "[y/N]",
        "[Y/n]",
        "(y/N)",
        "(Y/n)",
        "[yes/no]",
        "Press RETURN",
        "press ENTER",
        "Do you want to",
        "Would you like to",
        "Continue?",
        "Proceed?",
    ]

    /// Checks if the given output text ends with a prompt waiting for input
    private func detectsInputPrompt(in text: String) -> String? {
        // Get the last few lines of output to check for prompts
        let lines = text.components(separatedBy: .newlines)
        let lastLines = lines.suffix(3).joined(separator: "\n")

        for pattern in Self.inputPromptPatterns {
            if lastLines.contains(pattern) {
                return lastLines.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Prompts the user for input on the main thread using an alert dialog
    private func promptUser(message: String, isPassword: Bool) -> String? {
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Homebrew Requires Input"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Submit")
            alert.addButton(withTitle: "Cancel")

            if isPassword {
                let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
                secureField.placeholderString = "Enter password"
                alert.accessoryView = secureField
                alert.window.initialFirstResponder = secureField

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    result = secureField.stringValue
                }
            } else {
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
                textField.placeholderString = "Enter response"
                alert.accessoryView = textField
                alert.window.initialFirstResponder = textField

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    result = textField.stringValue
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    /// Runs a brew command interactively, prompting the user when input is required.
    /// Also configures SUDO_ASKPASS so that sudo can obtain passwords via GUI dialog
    /// even without a terminal (required for cask upgrades that need admin privileges).
    func runInteractiveCommand(arguments: [String], timeout: TimeInterval = upgradeCommandTimeout) -> Result<String, HomebrewError> {
        guard let brewPath = brewPath else {
            return .failure(.homebrewNotFound)
        }

        logger.info("Running interactive brew \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"

        // Configure SUDO_ASKPASS so sudo can prompt for password via GUI.
        // When sudo has no terminal, it uses the askpass helper to obtain credentials.
        // HOMEBREW_SUDO_THROUGH_SUDO_ASKPASS tells Homebrew to invoke sudo with -A flag,
        // which forces sudo to use the askpass helper instead of trying terminal input.
        if let askpassPath = askpassScriptPath {
            environment["SUDO_ASKPASS"] = askpassPath
            environment["HOMEBREW_SUDO_THROUGH_SUDO_ASKPASS"] = "1"
        }

        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let group = DispatchGroup()
        var didTimeout = false
        var userCancelled = false
        var allOutput = ""
        var exitStatus: Int32 = -1
        var processError: Error?

        // Lock for thread-safe access to allOutput
        let outputLock = NSLock()

        group.enter()

        DispatchQueue.global().async {
            do {
                try process.run()

                // Set up timeout
                let timeoutWorkItem = DispatchWorkItem {
                    if process.isRunning {
                        logger.warning("Interactive command timed out after \(timeout) seconds")
                        didTimeout = true
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                // Monitor output for prompts using a polling approach
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                // Use a timer to periodically check for available data and prompts
                var lastOutputTime = Date()
                let promptCheckInterval: TimeInterval = 0.5
                let staleOutputThreshold: TimeInterval = 2.0

                while process.isRunning && !didTimeout && !userCancelled {
                    var newData = false

                    // Read available stdout data
                    let stdoutData = stdoutHandle.availableData
                    if !stdoutData.isEmpty, let str = String(data: stdoutData, encoding: .utf8) {
                        outputLock.lock()
                        allOutput += str
                        outputLock.unlock()
                        newData = true
                        lastOutputTime = Date()
                    }

                    // Read available stderr data
                    let stderrData = stderrHandle.availableData
                    if !stderrData.isEmpty, let str = String(data: stderrData, encoding: .utf8) {
                        outputLock.lock()
                        allOutput += str
                        outputLock.unlock()
                        newData = true
                        lastOutputTime = Date()
                    }

                    // Check if output looks like a prompt and process has been idle
                    let timeSinceLastOutput = Date().timeIntervalSince(lastOutputTime)
                    if !newData && timeSinceLastOutput >= staleOutputThreshold {
                        outputLock.lock()
                        let currentOutput = allOutput
                        outputLock.unlock()

                        if let promptText = self.detectsInputPrompt(in: currentOutput) {
                            let isPassword = promptText.lowercased().contains("password")
                            logger.info("Detected input prompt: \(promptText)")

                            if let userInput = self.promptUser(message: promptText, isPassword: isPassword) {
                                // Write user input to process stdin
                                let inputData = (userInput + "\n").data(using: .utf8)!
                                stdinPipe.fileHandleForWriting.write(inputData)
                                lastOutputTime = Date() // Reset timer after sending input
                            } else {
                                // User cancelled
                                logger.info("User cancelled interactive prompt")
                                userCancelled = true
                                process.terminate()
                            }
                        }
                    }

                    if !newData {
                        Thread.sleep(forTimeInterval: promptCheckInterval)
                    }
                }

                // Read any remaining output after process exits
                if let remainingStdout = try? stdoutHandle.readToEnd(),
                   let str = String(data: remainingStdout, encoding: .utf8) {
                    outputLock.lock()
                    allOutput += str
                    outputLock.unlock()
                }
                if let remainingStderr = try? stderrHandle.readToEnd(),
                   let str = String(data: remainingStderr, encoding: .utf8) {
                    outputLock.lock()
                    allOutput += str
                    outputLock.unlock()
                }

                process.waitUntilExit()
                timeoutWorkItem.cancel()
                exitStatus = process.terminationStatus

            } catch {
                processError = error
            }
            group.leave()
        }

        group.wait()

        if userCancelled {
            return .failure(.userCancelled)
        }

        if didTimeout {
            return .failure(.timeout)
        }

        if let error = processError {
            logger.error("Interactive command failed: \(error.localizedDescription)")
            return .failure(.commandFailed(error.localizedDescription))
        }

        if exitStatus == 0 {
            logger.debug("Interactive command completed successfully")
            return .success(allOutput)
        } else {
            logger.error("Interactive command failed with exit code \(exitStatus): \(allOutput)")
            return .failure(.commandFailed(allOutput))
        }
    }

    func getHomebrewUpdates(runUpdateFirst: Bool = false) -> Result<[String], HomebrewError> {
        // Optionally run brew update first to get fresh data
        let shouldUpdate = runUpdateFirst || self.runUpdateFirst
        if shouldUpdate {
            logger.info("Running brew update first")
            let updateResult = runCommand(arguments: ["update"], timeout: updateCommandTimeout)
            if case .failure(let error) = updateResult {
                // Log but don't fail - we can still check outdated
                logger.warning("brew update failed: \(error.localizedDescription)")
            }
        }

        switch runCommand(arguments: ["outdated", "--json"], timeout: defaultCommandTimeout) {
        case .success(let output):
            guard let jsonStartIndex = output.firstIndex(of: "{") else {
                logger.error("Invalid JSON: No opening brace found")
                return .failure(.commandFailed("Invalid JSON: No opening brace found"))
            }

            let jsonDataString = String(output[jsonStartIndex...])

            if let jsonData = jsonDataString.data(using: .utf8) {
                if let dataModel = parseJSON(jsonData: jsonData) {
                    var output: [String] = [String]()
                    for formula in dataModel.formulae {
                        output.append("\(formula.name) (\(formula.installedVersions.joined(separator: ", "))) < \(formula.currentVersion)")
                    }
                    for cask in dataModel.casks {
                        output.append("\(cask.name) (\(cask.installedVersions.joined(separator: ", "))) != \(cask.currentVersion)")
                    }
                    logger.info("Found \(output.count) outdated packages")
                    return .success(output)
                } else {
                    logger.error("Unable to parse JSON data into object")
                    return .failure(.commandFailed("Unable to parse json data into object"))
                }
            } else {
                logger.error("Unable to parse 'brew outdated --json'")
                return .failure(.commandFailed("Unable to parse 'brew outdated --json'"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func upgradePackage(package: String) -> Result<Void, HomebrewError> {
        logger.info("Upgrading package: \(package)")
        switch runInteractiveCommand(arguments: ["upgrade", package]) {
        case .success:
            logger.info("Successfully upgraded \(package)")
            return .success(())
        case .failure(let error):
            logger.error("Failed to upgrade \(package): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func upgradeAllPackages() -> Result<Void, HomebrewError> {
        logger.info("Upgrading all packages")
        switch runInteractiveCommand(arguments: ["upgrade"]) {
        case .success:
            logger.info("Successfully upgraded all packages")
            return .success(())
        case .failure(let error):
            logger.error("Failed to upgrade all packages: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func installPackage(package: String) -> Result<Void, HomebrewError> {
        logger.info("Installing package: \(package)")
        switch runInteractiveCommand(arguments: ["install", package]) {
        case .success:
            logger.info("Successfully installed \(package)")
            return .success(())
        case .failure(let error):
            logger.error("Failed to install \(package): \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
