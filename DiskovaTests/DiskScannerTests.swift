import Foundation
import Testing

@testable import Diskova

/// Scanner tests run against a real temporary directory rather than a fake
/// filesystem. The whole point of this type is its behaviour against APFS —
/// allocated sizes, symlinks, hard links, bundles — and none of that survives
/// being mocked.
@Suite("Disk scanner", .serialized)
struct DiskScannerTests {
    // MARK: - Fixtures

    /// Creates a temporary directory that is deleted when `body` returns.
    private func withTemporaryDirectory<T>(
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "diskova-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try await body(root)
    }

    private func makeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    /// Runs a scan to completion and returns its outcome.
    private func scan(_ root: URL, options: ScanOptions = .default) async throws -> ScanOutcome {
        for await event in DiskScanner.scan(root, options: options) {
            switch event {
            case .completed(let outcome): return outcome
            case .failed(let failure): throw failure
            case .progress: continue
            }
        }
        throw ScanFailure.unreadable(root)
    }

    // MARK: - Counting

    @Test("Everything in the tree is counted once")
    func countsFilesAndFolders() async throws {
        try await withTemporaryDirectory { root in
            try makeFile(root.appending(path: "a.txt"), bytes: 1_000)
            try makeFile(root.appending(path: "nested/b.txt"), bytes: 2_000)
            try makeFile(root.appending(path: "nested/deeper/c.txt"), bytes: 3_000)

            let outcome = try await scan(root)

            #expect(outcome.root.fileCount == 3)
            #expect(outcome.root.directoryCount == 2)
            #expect(outcome.root.byteSize >= 6_000)
            #expect(outcome.unreadablePaths.isEmpty)
        }
    }

    @Test("Bigger files produce bigger nodes, and children are sorted")
    func sortsBySize() async throws {
        try await withTemporaryDirectory { root in
            try makeFile(root.appending(path: "small.txt"), bytes: 1_000)
            try makeFile(root.appending(path: "large.txt"), bytes: 400_000)
            try makeFile(root.appending(path: "medium.txt"), bytes: 60_000)

            let outcome = try await scan(root)
            #expect(outcome.root.children.map(\.name) == ["large.txt", "medium.txt", "small.txt"])
        }
    }

    @Test("Progress is reported before the result arrives")
    func reportsProgress() async throws {
        try await withTemporaryDirectory { root in
            for index in 0 ..< 60 {
                try makeFile(root.appending(path: "folder\(index % 6)/file\(index).bin"), bytes: 20_000)
            }

            var sawCompletion = false
            var finalProgress: ScanProgress?
            for await event in DiskScanner.scan(root) {
                switch event {
                case .progress(let progress): finalProgress = progress
                case .completed: sawCompletion = true
                case .failed(let failure): throw failure
                }
            }

            #expect(sawCompletion)
            #expect(finalProgress?.fileCount == 60)
            #expect(finalProgress?.directoryCount == 7)
        }
    }

    // MARK: - The things that make totals wrong

    @Test("Symbolic links are not followed, so nothing is counted twice")
    func doesNotFollowSymlinks() async throws {
        try await withTemporaryDirectory { root in
            let real = root.appending(path: "real")
            try makeFile(real.appending(path: "payload.bin"), bytes: 200_000)

            let link = root.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            let outcome = try await scan(root)
            #expect(outcome.root.fileCount == 1)
            #expect(outcome.root.directoryCount == 1)
        }
    }

    @Test("A symlink loop does not hang the scan")
    func survivesSymlinkLoops() async throws {
        try await withTemporaryDirectory { root in
            let inner = root.appending(path: "inner")
            try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: inner.appending(path: "loop"),
                withDestinationURL: root
            )
            try makeFile(inner.appending(path: "file.bin"), bytes: 1_000)

            let outcome = try await scan(root)
            #expect(outcome.root.fileCount == 1)
        }
    }

    @Test("Hard-linked files are charged once, not once per name")
    func countsHardLinksOnce() async throws {
        try await withTemporaryDirectory { root in
            let original = root.appending(path: "original.bin")
            try makeFile(original, bytes: 400_000)
            try FileManager.default.linkItem(
                at: original,
                to: root.appending(path: "same-bytes.bin")
            )

            let deduplicated = try await scan(root)
            var counted = ScanOptions.default
            counted.countHardLinkedFilesOnce = false
            let doubleCounted = try await scan(root, options: counted)

            // Both see two entries; only one of them believes the disk holds
            // 800 KB of data.
            #expect(deduplicated.root.fileCount == 2)
            #expect(doubleCounted.root.fileCount == 2)
            #expect(deduplicated.root.byteSize < doubleCounted.root.byteSize)
            #expect(doubleCounted.root.byteSize >= deduplicated.root.byteSize + 400_000)
        }
    }

    // MARK: - Options

    @Test("Hidden entries can be left out")
    func honoursHiddenFileOption() async throws {
        try await withTemporaryDirectory { root in
            try makeFile(root.appending(path: "visible.txt"), bytes: 1_000)
            try makeFile(root.appending(path: ".hidden.txt"), bytes: 1_000)

            let withHidden = try await scan(root)
            #expect(withHidden.root.fileCount == 2)

            var options = ScanOptions.default
            options.includeHiddenEntries = false
            let withoutHidden = try await scan(root, options: options)
            #expect(withoutHidden.root.fileCount == 1)
            #expect(withoutHidden.root.children.first?.name == "visible.txt")
        }
    }

    @Test("A bundle collapses to one item, with the size of everything inside")
    func collapsesBundles() async throws {
        try await withTemporaryDirectory { root in
            let bundle = root.appending(path: "Thing.app")
            try makeFile(bundle.appending(path: "Contents/MacOS/Thing"), bytes: 120_000)
            try makeFile(bundle.appending(path: "Contents/Resources/data.bin"), bytes: 80_000)

            let outcome = try await scan(root)
            let app = try #require(outcome.root.children.first { $0.name == "Thing.app" })

            #expect(app.isPackage)
            #expect(app.isDirectory == false)
            #expect(app.children.isEmpty)
            #expect(app.byteSize >= 200_000)
            #expect(app.kind == .application)
        }
    }

    @Test("Turning the bundle option off lets you walk inside")
    func canOpenBundles() async throws {
        try await withTemporaryDirectory { root in
            let bundle = root.appending(path: "Thing.app")
            try makeFile(bundle.appending(path: "Contents/MacOS/Thing"), bytes: 10_000)

            var options = ScanOptions.default
            options.treatBundlesAsSingleItems = false
            let outcome = try await scan(root, options: options)
            let app = try #require(outcome.root.children.first { $0.name == "Thing.app" })

            #expect(app.isDirectory)
            #expect(app.children.isEmpty == false)
        }
    }

    // MARK: - Failure and cancellation

    @Test("Pointing the scanner at a file is reported, not ignored")
    func rejectsNonFolders() async throws {
        try await withTemporaryDirectory { root in
            let file = root.appending(path: "a.txt")
            try makeFile(file, bytes: 10)

            var failure: ScanFailure?
            for await event in DiskScanner.scan(file) {
                if case .failed(let reported) = event { failure = reported }
            }
            #expect(failure == .notAFolder(file.standardizedFileURL))
        }
    }

    @Test("A path that does not exist is reported as unreadable")
    func rejectsMissingPaths() async throws {
        let missing = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString)")
        var failure: ScanFailure?
        for await event in DiskScanner.scan(missing) {
            if case .failed(let reported) = event { failure = reported }
        }
        #expect(failure == .unreadable(missing.standardizedFileURL))
    }

    @Test("Abandoning the stream stops the scan instead of leaking it")
    func stopsWhenTheConsumerStops() async throws {
        try await withTemporaryDirectory { root in
            for index in 0 ..< 400 {
                try makeFile(root.appending(path: "d\(index % 20)/f\(index).bin"), bytes: 4_000)
            }

            // Taking a single event and walking away must return promptly and
            // must not deliver a result afterwards.
            var eventsSeen = 0
            for await _ in DiskScanner.scan(root) {
                eventsSeen += 1
                break
            }
            #expect(eventsSeen == 1)
        }
    }

    @Test("An empty folder scans to an empty tree rather than failing")
    func handlesEmptyFolders() async throws {
        try await withTemporaryDirectory { root in
            let outcome = try await scan(root)
            #expect(outcome.root.children.isEmpty)
            #expect(outcome.root.fileCount == 0)
        }
    }

    @Test("Scanning records how long it took")
    func recordsElapsedTime() async throws {
        try await withTemporaryDirectory { root in
            try makeFile(root.appending(path: "a.txt"), bytes: 10)
            let outcome = try await scan(root)
            #expect(outcome.elapsed >= 0)
            #expect(outcome.options == ScanOptions.default)
        }
    }
}

