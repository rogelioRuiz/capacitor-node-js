import Foundation
import UIKit
import Capacitor

@objc(CapacitorNodeJSPlugin)
public class NodeJSPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CapacitorNodeJSPlugin"
    public let jsName = "CapacitorNodeJS"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "whenReady", returnType: CAPPluginReturnPromise),
    ]

    private static let CHANNEL_NAME_APP = "APP_CHANNEL"
    private static let CHANNEL_NAME_EVENT = "EVENT_CHANNEL"

    private let implementation = NodeJS()

    override public func load() {
        let nodeDir = getConfig().getString("nodeDir") ?? "nodejs"
        let startMode = getConfig().getString("startMode") ?? "auto"

        // Register for app lifecycle notifications (Capacitor 8+ removed handleOnResume/Pause)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        if startMode == "auto" {
            implementation.startEngine(
                projectDir: nodeDir,
                mainFile: nil,
                args: [],
                env: [:],
                onReceive: { [weak self] channel, message in
                    self?.receiveMessage(channelName: channel, channelMessage: message)
                },
                onStarted: { error in
                    if let error = error {
                        NSLog("CapacitorNodeJS: Auto-start failed: \(error)")
                    }
                }
            )
        }
    }

    // MARK: - Lifecycle

    @objc private func appDidBecomeActive() {
        if implementation.engineStarted && implementation.engineReady {
            implementation.sendMessage(NodeJSPlugin.CHANNEL_NAME_APP, eventName: "resume", args: [])
        }
    }

    @objc private func appWillResignActive() {
        if implementation.engineStarted && implementation.engineReady {
            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }

            implementation.sendMessage(NodeJSPlugin.CHANNEL_NAME_APP, eventName: "pause", args: [])

            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
    }

    // MARK: - Plugin Methods

    @objc func start(_ call: CAPPluginCall) {
        let startMode = getConfig().getString("startMode") ?? "auto"
        guard startMode == "manual" else {
            call.reject("Manual startup of the Node.js engine is not enabled.")
            return
        }

        let nodeDir = call.getString("nodeDir") ?? getConfig().getString("nodeDir") ?? "nodejs"
        let script = call.getString("script")
        let argsArray = call.getArray("args", String.self) ?? []
        let envObj = call.getObject("env") ?? [:]

        var env: [String: String] = [:]
        for (key, value) in envObj {
            if let v = value as? String {
                env[key] = v
            }
        }

        implementation.startEngine(
            projectDir: nodeDir,
            mainFile: script,
            args: argsArray,
            env: env,
            onReceive: { [weak self] channel, message in
                self?.receiveMessage(channelName: channel, channelMessage: message)
            },
            onStarted: { error in
                if let error = error {
                    call.reject(error)
                } else {
                    call.resolve()
                }
            }
        )
    }

    @objc func send(_ call: CAPPluginCall) {
        guard implementation.engineStarted else {
            call.reject("The Node.js engine has not been started yet.")
            return
        }
        guard implementation.engineReady else {
            call.reject("The Node.js engine is not ready yet.")
            return
        }

        guard let eventName = call.getString("eventName"), !eventName.isEmpty else {
            call.reject("Required parameter 'eventName' was not specified.")
            return
        }

        let args = call.getArray("args") ?? []
        implementation.sendMessage(NodeJSPlugin.CHANNEL_NAME_EVENT, eventName: eventName, args: args)
        call.resolve()
    }

    @objc func whenReady(_ call: CAPPluginCall) {
        guard implementation.engineStarted else {
            call.reject("The Node.js engine has not been started yet.")
            return
        }

        implementation.resolveWhenReady {
            call.resolve()
        }
    }

    // MARK: - Message Routing

    private func receiveMessage(channelName: String, channelMessage: String) {
        guard let data = channelMessage.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = json["eventName"] as? String else {
            NSLog("CapacitorNodeJS: Failed to deserialize message from Node.js process.")
            return
        }

        let eventMessage = json["eventMessage"] as? String ?? ""
        var args: [Any] = []
        if !eventMessage.isEmpty,
           let argsData = eventMessage.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [Any] {
            args = parsed
        }

        if channelName == NodeJSPlugin.CHANNEL_NAME_APP && eventName == "ready" {
            implementation.setReady()
        } else if channelName == NodeJSPlugin.CHANNEL_NAME_EVENT {
            notifyListeners(eventName, data: ["args": args])
        }
    }
}
