//
//  SafariWebExtensionHandler.swift
//  Papyrus Web Clipper Extension
//
//  Handles native messages from the Safari browser extension.
//  PDF import now goes through BrowserImportServer (HTTP POST to localhost).
//  This handler's only job is to wake Papyrus when it is not running.
//

import AppKit
import Foundation
import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private enum BundleID {
        static let papyrus = "com.papyrus.app"
    }

    private enum NativeMessageType {
        static let openPapyrus = "OPEN_PAPYRUS"
    }

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let message = request?.userInfo?[SFExtensionMessageKey]

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@", String(describing: message))

        handle(message, context: context)
    }

    private func handle(_ message: Any?, context: NSExtensionContext) {
        guard let payload = message as? [String: Any],
              let type = payload["type"] as? String else {
            complete(context, payload: ["ok": false, "error": "Unsupported native message."])
            return
        }

        switch type {
        case NativeMessageType.openPapyrus:
            openPapyrus(context: context)
        default:
            complete(context, payload: ["ok": false, "error": "Unsupported native message type."])
        }
    }

    private func openPapyrus(context: NSExtensionContext) {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BundleID.papyrus) else {
            complete(context, payload: ["ok": false, "error": "Papyrus is not installed."])
            return
        }

        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: BundleID.papyrus).isEmpty

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = !isRunning
        configuration.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
            if let error {
                self.complete(context, payload: ["ok": false, "error": error.localizedDescription])
                return
            }
            self.complete(context, payload: ["ok": true])
        }
    }

    private func complete(_ context: NSExtensionContext, payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
