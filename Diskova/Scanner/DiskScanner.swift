import Foundation

/// Walks a folder tree and measures it.
///
/// The scanner is a free function rather than an object: it owns no state that
/// outlives a scan, and the tree it returns is immutable, so there is nothing to
/// keep in sync afterwards. Call ``scan(_:options:)`` and consume the stream.
///
/// ## How it stays fast
///
/// A full startup disk is a few million entries, and the work is almost
/// entirely waiting on the filesystem rather than computing. So:
///
/// - The top two levels of the tree are walked **in parallel** with a task
///   group; deeper levels recurse on whichever task reached them. Going wide
///   at the top is where the win is — `~/Library`, `/Applications` and
///   `/System` can all be read at once — while recursing sequentially deeper
///   down avoids spawning a task per folder on a disk with 200,000 of them.
/// - Sizes come from the directory listing itself. `contentsOfDirectory` is
///   asked for every attribute up front, which lets the kernel batch the
///   lookups, instead of calling `stat` once per file afterwards.
/// - Counters live in one actor and are updated **once per folder**, in a
///   batch, not once per file. Scanning is fast enough that per-file actor hops
///   would show up in the profile.
///
/// ## What it deliberately does not do
///
/// - It never follows symbolic links. They make the tree a graph, which means
///   both infinite loops and double counting.
/// - It never crosses onto another volume unless asked
///   (``ScanOptions/crossVolumeBoundaries``).
/// - It never counts the same bytes twice through hard links
///   (``ScanOptions/countHardLinkedFilesOnce``).
enum DiskScanner {
    /// Folders beyond this depth are not descended into.
    ///
    /// Real trees are nowhere near this deep; the cap exists so that a
    /// pathological structure cannot recurse the stack to death.
    static let maximumDepth = 128

    /// Levels of the tree that get their own parallel tasks.
    private static let parallelDepthLimit = 2

    /// How often progress is published while scanning.
    private static let progressInterval = Duration.milliseconds(100)

    /// Attributes fetched for every entry, in one go.
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .linkCountKey,
    ]

    /// Scans `root`, reporting progress and then a single terminal event.
    ///
    /// Cancellation is cooperative and immediate: stop consuming the stream (or
    /// cancel the consuming task) and the scan stops without emitting a result.
    ///
    /// - Returns: a stream of ``ScanEvent`` that finishes after exactly one
    ///   ``ScanEvent/completed(_:)`` or ``ScanEvent/failed(_:)``, unless the
    ///   scan was cancelled, in which case it finishes with neither.
    static func scan(_ root: URL, options: ScanOptions = .default) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let work = Task.detached(priority: .userInitiated) {
                await perform(root: root, options: options, continuation: continuation)
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - Driving a scan

    private static func perform(
        root: URL,
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let startedAt = Date()
        let target = root.standardizedFileURL

        guard let values = try? target.resourceValues(forKeys: [.isDirectoryKey]) else {
            continuation.yield(.failed(.unreadable(target)))
            continuation.finish()
            return
        }
        guard values.isDirectory == true else {
            continuation.yield(.failed(.notAFolder(target)))
            continuation.finish()
            return
        }

        let tally = ScanTally()
        let boundaryDevice = options.crossVolumeBoundaries ? nil : deviceIdentifier(of: target)

        // Publish progress on a timer rather than on every change, so a scan
        // that discovers 50,000 files a second does not ask SwiftUI to render
        // 50,000 times.
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: progressInterval)
                guard !Task.isCancelled else { break }
                continuation.yield(.progress(await tally.snapshot()))
            }
        }

        let tree = await walk(
            folder: target,
            depth: 0,
            options: options,
            tally: tally,
            boundaryDevice: boundaryDevice
        )
        ticker.cancel()

        guard !Task.isCancelled, let tree else {
            continuation.finish()
            return
        }

        continuation.yield(.progress(await tally.snapshot()))
        continuation.yield(.completed(
            ScanOutcome(
                root: tree,
                unreadablePaths: await tally.unreadablePaths,
                elapsed: Date().timeIntervalSince(startedAt),
                options: options
            )
        ))
        continuation.finish()
    }

    // MARK: - Walking

    /// Measures one folder and everything below it.
    ///
    /// - Returns: the folder's node, or `nil` if the scan was cancelled partway
    ///   through. A folder that cannot be read is *not* `nil` — it comes back
    ///   as an empty node and is noted in ``ScanTally/unreadablePaths``, so an
    ///   unreadable corner of the disk does not discard the rest of the scan.
    private static func walk(
        folder: URL,
        depth: Int,
        options: ScanOptions,
        tally: ScanTally,
        boundaryDevice: dev_t?
    ) async -> FileNode? {
        if Task.isCancelled { return nil }

        guard depth < maximumDepth else {
            await tally.noteUnreadable(folder)
            return FileNode.directory(url: folder, children: [])
        }

        var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHiddenEntries {
            enumerationOptions.insert(.skipsHiddenFiles)
        }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(resourceKeys),
                options: enumerationOptions
            )
        } catch {
            await tally.noteUnreadable(folder)
            return FileNode.directory(url: folder, children: [])
        }

        await tally.noteFolder(path: folder.path)

        var leaves: [FileNode] = []
        var subfolders: [URL] = []
        var batchedFileCount = 0
        var batchedByteSize: Int64 = 0

        for entry in entries {
            if Task.isCancelled { return nil }
            guard let values = try? entry.resourceValues(forKeys: resourceKeys) else { continue }

            // Symlinks are skipped outright. Following them would both loop
            // forever on a cycle and count the target's bytes twice.
            if values.isSymbolicLink == true { continue }

            let isFolder = values.isDirectory ?? false
            let isBundle = values.isPackage ?? false

            if isFolder, isBundle, options.treatBundlesAsSingleItems {
                // Walk the bundle to find out how big it is, then throw the
                // detail away and keep a single leaf. Its files are already
                // counted in the tally by the recursive walk, so they are not
                // added again here.
                guard let inside = await walk(
                    folder: entry,
                    depth: depth + 1,
                    options: options,
                    tally: tally,
                    boundaryDevice: boundaryDevice
                ) else { return nil }

                leaves.append(FileNode.file(
                    url: entry,
                    byteSize: inside.byteSize,
                    kind: FileKind.forFile(named: entry.lastPathComponent),
                    isPackage: true
                ))
                continue
            }

            if isFolder {
                if let boundaryDevice,
                   let device = deviceIdentifier(of: entry),
                   device != boundaryDevice {
                    // A different volume is mounted here. Leave it alone.
                    continue
                }
                subfolders.append(entry)
                continue
            }

            var byteSize = Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )

            if options.countHardLinkedFilesOnce,
               let links = values.linkCount, links > 1,
               let identity = FileIdentity(url: entry),
               await tally.claimHardLink(identity) == false {
                // Already counted under another name. Keep the entry visible so
                // the tree still reflects reality, but charge it nothing —
                // deleting it would not free anything either.
                byteSize = 0
            }

            batchedFileCount += 1
            batchedByteSize += byteSize
            leaves.append(FileNode.file(
                url: entry,
                byteSize: byteSize,
                kind: FileKind.forFile(named: entry.lastPathComponent)
            ))
        }

        await tally.noteFiles(count: batchedFileCount, byteSize: batchedByteSize)

        let scannedSubfolders: [FileNode]
        if depth < parallelDepthLimit, subfolders.count > 1 {
            scannedSubfolders = await withTaskGroup(
                of: FileNode?.self,
                returning: [FileNode].self
            ) { group in
                for subfolder in subfolders {
                    group.addTask {
                        await walk(
                            folder: subfolder,
                            depth: depth + 1,
                            options: options,
                            tally: tally,
                            boundaryDevice: boundaryDevice
                        )
                    }
                }
                var collected: [FileNode] = []
                for await child in group {
                    if let child { collected.append(child) }
                }
                return collected
            }
        } else {
            var collected: [FileNode] = []
            for subfolder in subfolders {
                guard let child = await walk(
                    folder: subfolder,
                    depth: depth + 1,
                    options: options,
                    tally: tally,
                    boundaryDevice: boundaryDevice
                ) else { return nil }
                collected.append(child)
            }
            scannedSubfolders = collected
        }

        if Task.isCancelled { return nil }

        return FileNode.directory(
            url: folder,
            children: leaves + scannedSubfolders,
            ownByteSize: allocatedSize(of: folder)
        )
    }

    // MARK: - Filesystem helpers

    /// Size of a directory entry itself, not counting its contents. Tiny per
    /// folder, but a disk with 300,000 folders hides several gigabytes here.
    private static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
              let size = values.totalFileAllocatedSize
        else { return 0 }
        return Int64(size)
    }

    /// Which volume a path lives on. Used to stop at mount points.
    private static func deviceIdentifier(of url: URL) -> dev_t? {
        var info = stat()
        let succeeded = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else { return false }
            return lstat(pointer, &info) == 0
        }
        return succeeded ? info.st_dev : nil
    }
}

/// The one piece of shared mutable state in a scan.
///
/// Kept as an actor so the parallel walks can update it without locks. Updates
/// are batched per folder by the caller, which keeps the number of hops in
/// proportion to the folder count rather than the file count.
private actor ScanTally {
    private(set) var fileCount = 0
    private(set) var directoryCount = 0
    private(set) var byteSize: Int64 = 0
    private(set) var currentPath = ""
    private(set) var unreadablePaths: [URL] = []
    private var claimedHardLinks: Set<FileIdentity> = []

    /// Cap on remembered unreadable paths. A machine without Full Disk Access
    /// can refuse hundreds of thousands of folders, and the UI only ever shows
    /// a handful plus a count.
    private static let unreadablePathLimit = 1_000
    private var unreadableOverflow = 0

    func noteFolder(path: String) {
        directoryCount += 1
        currentPath = path
    }

    func noteFiles(count: Int, byteSize bytes: Int64) {
        fileCount += count
        byteSize += bytes
    }

    func noteUnreadable(_ url: URL) {
        if unreadablePaths.count < Self.unreadablePathLimit {
            unreadablePaths.append(url)
        } else {
            unreadableOverflow += 1
        }
    }

    /// Records a hard-linked file's identity.
    ///
    /// - Returns: `true` the first time an identity is seen — the caller should
    ///   charge the file its full size — and `false` afterwards.
    func claimHardLink(_ identity: FileIdentity) -> Bool {
        claimedHardLinks.insert(identity).inserted
    }

    func snapshot() -> ScanProgress {
        ScanProgress(
            fileCount: fileCount,
            directoryCount: directoryCount,
            byteSize: byteSize,
            currentPath: currentPath
        )
    }
}
