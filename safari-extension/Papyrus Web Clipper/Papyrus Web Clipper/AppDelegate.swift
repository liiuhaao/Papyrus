//
//  AppDelegate.swift
//  Papyrus Web Clipper
//
//  Created by 刘浩 on 2026/3/27.
//

import Cocoa
import SafariServices

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        let id = "com.papyrus.app.web-clipper.Extension"
        var done = false

        SFSafariApplication.showPreferencesForExtension(withIdentifier: id) { error in
            done = true
            if let error = error as NSError?, error.domain == "SFErrorDomain" {
                DispatchQueue.main.async { self.showSetupAlert() }
            } else {
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        }

        // showPreferencesForExtension hangs (no callback) when Safari cannot see the
        // extension, e.g. "Allow unsigned extensions" is disabled. Show setup alert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard !done else { return }
            self.showSetupAlert()
        }
    }

    private func showSetupAlert() {
        let alert = NSAlert()
        alert.messageText = "Safari Extension Not Visible"
        alert.informativeText = """
            Enable unsigned extensions in Safari first:

            1. Safari › Settings › Advanced
               ☑ Show features for web developers
            2. Safari › Settings › Developer › Extensions
               ☑ Allow unsigned extensions

            Then click "Set Up in Safari" again.
            Note: this must be re-enabled after each Mac restart.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }

}
