import Foundation
import CapacitorNodejsBridge

@objc public class NodeJS: NSObject, NodeProcessDelegate {

    private static let LOGGER_TAG = "CapacitorNodeJS"
    private static let PREFS_APP_UPDATED_TIME = "CapacitorNodeJS_AppUpdateTime"

    private let nodeProcess = NodeProcess()
    private var isEngineStarted = false
    private var isEngineReady = false
    private var whenReadyCallbacks: [() -> Void] = []
    private var receiveCallback: ((String, String) -> Void)?
    private var nodeThread: Thread?

    public var engineStarted: Bool { isEngineStarted }
    public var engineReady: Bool { isEngineReady }

    public func startEngine(
        projectDir: String,
        mainFile: String?,
        args: [String],
        env: [String: String],
        onReceive: @escaping (String, String) -> Void,
        onStarted: @escaping (String?) -> Void
    ) {
        if isEngineStarted {
            onStarted("The Node.js engine has already been started.")
            return
        }
        isEngineStarted = true
        receiveCallback = onReceive
        nodeProcess.delegate = self

        let thread = Thread { [weak self] in
            guard let self = self else { return }

            // iOS sandbox paths
            let libraryPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!
            let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!

            let basePath = (libraryPath as NSString).appendingPathComponent("nodejs")
            let projectPath = (basePath as NSString).appendingPathComponent("public")
            let modulesPath = (basePath as NSString).appendingPathComponent("builtin_modules")
            let dataPath = (basePath as NSString).appendingPathComponent("data")

            // Copy assets from bundle to sandbox
            let copySuccess = self.copyNodeProjectFromBundle(
                projectDir: projectDir,
                projectPath: projectPath,
                modulesPath: modulesPath
            )

            if !copySuccess {
                DispatchQueue.main.async { onStarted("Unable to copy the Node.js project from bundle.") }
                return
            }

            let fm = FileManager.default
            if !fm.fileExists(atPath: projectPath) {
                DispatchQueue.main.async { onStarted("Unable to access the Node.js project. (No such directory)") }
                return
            }

            // Create persistent data directory
            try? fm.createDirectory(atPath: dataPath, withIntermediateDirectories: true)

            // Resolve main entry point
            var mainScript = "index.js"
            if let mf = mainFile, !mf.isEmpty {
                mainScript = mf
            } else {
                let packageJsonPath = (projectPath as NSString).appendingPathComponent("package.json")
                if fm.fileExists(atPath: packageJsonPath),
                   let data = fm.contents(atPath: packageJsonPath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pkgMain = json["main"] as? String, !pkgMain.isEmpty {
                    mainScript = pkgMain
                }
            }

            let mainPath = (projectPath as NSString).appendingPathComponent(mainScript)
            if !fm.fileExists(atPath: mainPath) {
                DispatchQueue.main.async { onStarted("Unable to access main script of the Node.js project. (No such file)") }
                return
            }

            // Build NODE_PATH: project dir + builtin_modules dir
            let modulePaths = "\(projectPath):\(modulesPath)"

            // Build environment
            var nodeEnv = env
            nodeEnv["DATADIR"] = dataPath
            nodeEnv["NODE_PATH"] = modulePaths
            nodeEnv["TMPDIR"] = cachePath

            // Build argv: ["node", mainPath, ...args]
            var arguments = ["node", mainPath]
            arguments.append(contentsOf: args)

            DispatchQueue.main.async { onStarted(nil) } // nil = success

            // Start Node.js — blocks until engine exits
            self.nodeProcess.start(withArguments: arguments, environmentVariables: nodeEnv)
        }

        thread.stackSize = 2 * 1024 * 1024 // 2MB stack required by Node.js
        thread.name = "NodeJS-Engine"
        thread.qualityOfService = .userInitiated
        self.nodeThread = thread
        thread.start()
    }

    // MARK: - Engine Ready

    public func setReady() {
        isEngineReady = true
        for callback in whenReadyCallbacks {
            callback()
        }
        whenReadyCallbacks.removeAll()
    }

    public func resolveWhenReady(_ callback: @escaping () -> Void) {
        if isEngineReady {
            callback()
        } else {
            whenReadyCallbacks.append(callback)
        }
    }

    // MARK: - Message Sending

    public func sendMessage(_ channelName: String, eventName: String, args: [Any]) {
        let eventMessage: String
        if let data = try? JSONSerialization.data(withJSONObject: args),
           let str = String(data: data, encoding: .utf8) {
            eventMessage = str
        } else {
            eventMessage = "[]"
        }

        let payload: [String: Any] = [
            "eventName": eventName,
            "eventMessage": eventMessage
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let channelMessage = String(data: data, encoding: .utf8) {
            nodeProcess.send(toChannel: channelName, message: channelMessage)
        }
    }

    // MARK: - NodeProcessDelegate

    public func didReceiveMessage(onChannel channel: String, message: String) {
        receiveCallback?(channel, message)
    }

    // MARK: - Asset Copying

    private func copyNodeProjectFromBundle(projectDir: String, projectPath: String, modulesPath: String) -> Bool {
        let fm = FileManager.default
        let appUpdated = isAppUpdated()

        var success = true

        // Copy user's Node.js project files from bundle
        // Files are expected at: App.app/public/{projectDir}/
        if let bundleProjectPath = Bundle.main.path(forResource: projectDir, ofType: nil, inDirectory: "public") {
            if fm.fileExists(atPath: projectPath) && appUpdated {
                do {
                    try fm.removeItem(atPath: projectPath)
                } catch {
                    NSLog("\(NodeJS.LOGGER_TAG): Failed to remove old project directory: \(error)")
                    success = false
                }
            }

            if !fm.fileExists(atPath: projectPath) {
                do {
                    let parentDir = (projectPath as NSString).deletingLastPathComponent
                    try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                    try fm.copyItem(atPath: bundleProjectPath, toPath: projectPath)
                } catch {
                    NSLog("\(NodeJS.LOGGER_TAG): Failed to copy project from bundle: \(error)")
                    success = false
                }
            }
        } else {
            NSLog("\(NodeJS.LOGGER_TAG): Node.js project directory '\(projectDir)' not found in bundle/public/")
            success = false
        }

        // Copy builtin_modules from the plugin's resource bundle
        let builtinModulesSource = findBuiltinModulesInBundle()
        if let source = builtinModulesSource {
            if fm.fileExists(atPath: modulesPath) && appUpdated {
                do {
                    try fm.removeItem(atPath: modulesPath)
                } catch {
                    NSLog("\(NodeJS.LOGGER_TAG): Failed to remove old builtin_modules: \(error)")
                    success = false
                }
            }

            if !fm.fileExists(atPath: modulesPath) {
                do {
                    let parentDir = (modulesPath as NSString).deletingLastPathComponent
                    try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                    try fm.copyItem(atPath: source, toPath: modulesPath)
                } catch {
                    NSLog("\(NodeJS.LOGGER_TAG): Failed to copy builtin_modules from bundle: \(error)")
                    success = false
                }
            }
        } else {
            NSLog("\(NodeJS.LOGGER_TAG): builtin_modules not found in any bundle.")
            success = false
        }

        saveAppUpdateTime()
        return success
    }

    /// Search for builtin_modules in the main bundle and plugin resource bundles
    private func findBuiltinModulesInBundle() -> String? {
        // Check main bundle root first
        if let path = Bundle.main.path(forResource: "builtin_modules", ofType: nil) {
            return path
        }

        // Check inside public/ directory (Capacitor apps put assets here)
        if let path = Bundle.main.path(forResource: "builtin_modules", ofType: nil, inDirectory: "public") {
            return path
        }

        // Check plugin resource bundles (CocoaPods puts resources in sub-bundles)
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath
        if let contents = try? fm.contentsOfDirectory(atPath: bundlePath) {
            for item in contents where item.hasSuffix(".bundle") {
                let subBundlePath = (bundlePath as NSString).appendingPathComponent(item)
                if let subBundle = Bundle(path: subBundlePath) {
                    if let path = subBundle.path(forResource: "builtin_modules", ofType: nil) {
                        return path
                    }
                }
            }
        }

        return nil
    }

    private func isAppUpdated() -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let storedVersion = UserDefaults.standard.string(forKey: NodeJS.PREFS_APP_UPDATED_TIME) ?? ""
        return currentVersion != storedVersion
    }

    private func saveAppUpdateTime() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        UserDefaults.standard.set(currentVersion, forKey: NodeJS.PREFS_APP_UPDATED_TIME)
    }
}
