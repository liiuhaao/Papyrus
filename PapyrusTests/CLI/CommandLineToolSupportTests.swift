import Foundation
import Testing
@testable import PapyrusCore

struct CommandLineToolSupportTests {
    @Test
    func installPlanRequestsInstallForApplicationsBundle() throws {
        let context = try makeContext(bundleURL: URL(fileURLWithPath: "/Applications/Papyrus.app"))

        let plan = CommandLineToolSupport.installPlan(
            bundleURL: context.bundleURL,
            bundledCLIURL: context.bundledCLIURL,
            installDestinationURL: context.installDestinationURL
        )

        #expect(
            plan == .install(
                source: context.bundledCLIURL,
                destination: context.installDestinationURL,
                requiresPrivilegedInstall: false
            )
        )
    }

    @Test
    func installPlanSkipsRepoLocalBundle() throws {
        let context = try makeContext()

        let plan = CommandLineToolSupport.installPlan(
            bundleURL: context.bundleURL,
            bundledCLIURL: context.bundledCLIURL,
            installDestinationURL: context.installDestinationURL
        )

        #expect(plan == .unavailable)
    }

    @Test
    func installPlanSkipsMountedDmgBundle() throws {
        let context = try makeContext()
        let mountedBundleURL = URL(fileURLWithPath: "/Volumes/Papyrus/Papyrus.app")

        let plan = CommandLineToolSupport.installPlan(
            bundleURL: mountedBundleURL,
            bundledCLIURL: context.bundledCLIURL,
            installDestinationURL: context.installDestinationURL
        )

        #expect(plan == .unavailable)
    }

    @Test
    func installPlanRepairsStalePapyrusSymlink() throws {
        let context = try makeContext(bundleURL: URL(fileURLWithPath: "/Applications/Papyrus.app"))
        let staleTarget = context.rootURL
            .appendingPathComponent("old")
            .appendingPathComponent("PapyrusCLI")

        try makeExecutable(at: staleTarget)
        try FileManager.default.createSymbolicLink(
            at: context.installDestinationURL,
            withDestinationURL: staleTarget
        )

        let plan = CommandLineToolSupport.installPlan(
            bundleURL: context.bundleURL,
            bundledCLIURL: context.bundledCLIURL,
            installDestinationURL: context.installDestinationURL
        )

        #expect(
            plan == .install(
                source: context.bundledCLIURL,
                destination: context.installDestinationURL,
                requiresPrivilegedInstall: false
            )
        )
    }

    @Test
    func installPlanDoesNotOverwriteUnrelatedCommand() throws {
        let context = try makeContext(bundleURL: URL(fileURLWithPath: "/Applications/Papyrus.app"))
        let unrelatedTarget = context.rootURL
            .appendingPathComponent("other")
            .appendingPathComponent("papyrus")

        try makeExecutable(at: unrelatedTarget)
        try FileManager.default.createSymbolicLink(
            at: context.installDestinationURL,
            withDestinationURL: unrelatedTarget
        )

        let plan = CommandLineToolSupport.installPlan(
            bundleURL: context.bundleURL,
            bundledCLIURL: context.bundledCLIURL,
            installDestinationURL: context.installDestinationURL
        )

        #expect(plan == .blockedByExistingCommand(destination: context.installDestinationURL))
    }

    private func makeContext(bundleURL: URL? = nil) throws -> InstallContext {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let actualBundleURL = bundleURL ?? rootURL.appendingPathComponent("Papyrus.app", isDirectory: true)
        let bundledCLIURL = actualBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("papyrus")
        let installDirectoryURL = rootURL
            .appendingPathComponent("usr", isDirectory: true)
            .appendingPathComponent("local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let installDestinationURL = installDirectoryURL.appendingPathComponent("papyrus")

        try FileManager.default.createDirectory(
            at: bundledCLIURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: installDirectoryURL,
            withIntermediateDirectories: true
        )
        try makeExecutable(at: bundledCLIURL)

        return InstallContext(
            rootURL: rootURL,
            bundleURL: actualBundleURL,
            bundledCLIURL: bundledCLIURL,
            installDestinationURL: installDestinationURL
        )
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private struct InstallContext {
        let rootURL: URL
        let bundleURL: URL
        let bundledCLIURL: URL
        let installDestinationURL: URL
    }
}
