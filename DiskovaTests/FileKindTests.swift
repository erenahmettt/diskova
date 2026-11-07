import Foundation
import Testing

@testable import Diskova

@Suite("File classification")
struct FileKindTests {
    @Test("Common extensions land in the expected category", arguments: [
        ("holiday.JPG", FileKind.image),
        ("holiday.heic", FileKind.image),
        ("movie.mkv", FileKind.video),
        ("song.flac", FileKind.audio),
        ("thesis.pdf", FileKind.document),
        ("notes.md", FileKind.document),
        ("backup.tar.gz", FileKind.archive),
        ("Installer.dmg", FileKind.archive),
        ("Xcode.app", FileKind.application),
        ("main.swift", FileKind.code),
        ("schema.sqlite", FileKind.code),
        ("model.gguf", FileKind.code),
        ("Helvetica.ttf", FileKind.code),
        ("object.o", FileKind.developer),
        ("Module.swiftmodule", FileKind.developer),
    ])
    func classifiesByExtension(name: String, expected: FileKind) {
        #expect(FileKind.forFile(named: name) == expected)
    }

    @Test("Extensions are matched without regard to case")
    func classificationIsCaseInsensitive() {
        #expect(FileKind.forFile(named: "a.PnG") == .image)
        #expect(FileKind.forFile(named: "a.png") == .image)
    }

    @Test("A dotfile counts as configuration, a bare name does not")
    func classifiesDotfiles() {
        #expect(FileKind.forFile(named: ".zshrc") == .code)
        #expect(FileKind.forFile(named: "README") == .other)
    }

    @Test("Unknown extensions fall through to other")
    func unknownExtensionsFallThrough() {
        #expect(FileKind.forFile(named: "mystery.qqqq") == .other)
    }

    @Test("Build and cache folders are recognised by name", arguments: [
        "node_modules", "DerivedData", "__pycache__", ".venv", "build", "Pods",
    ])
    func recognisesBuildFolders(name: String) {
        #expect(FileKind.forDirectory(named: name) == .developer)
    }

    @Test("An ordinary folder is just a folder")
    func ordinaryFoldersAreFolders() {
        #expect(FileKind.forDirectory(named: "Documents") == .folder)
        #expect(FileKind.forDirectory(named: "Holiday Photos") == .folder)
    }

    @Test("Only build output is flagged as safe to delete")
    func onlyBuildOutputIsReclaimable() {
        #expect(FileKind.developer.isUsuallyReclaimable)
        for kind in FileKind.allCases where kind != .developer {
            #expect(kind.isUsuallyReclaimable == false)
        }
    }

    @Test("Every category has a label, an icon and a group")
    func everyKindIsPresentable() {
        for kind in FileKind.allCases {
            #expect(kind.symbolName.isEmpty == false)
            #expect(String(localized: kind.displayName).isEmpty == false)
            #expect(kind.group.kinds.contains(kind))
        }
    }

    @Test("Each palette's legend covers every category exactly once")
    func legendsAreComplete() {
        for palette in TreemapPalette.allCases {
            let covered = palette.legendEntries.flatMap(\.kinds)
            // Folders are drawn as frames, so the detailed legend omits them.
            let expected = palette == .detailed
                ? Set(FileKind.allCases).subtracting([.folder])
                : Set(FileKind.allCases)
            #expect(Set(covered) == expected)
            #expect(covered.count == Set(covered).count, "a category appears in two legend rows")
        }
    }
}

@Suite("Formatting")
struct FormatTests {
    @Test("Tiny shares read as a floor rather than as zero")
    func percentHasAFloor() {
        #expect(Format.percent(0.0000001).hasPrefix("<"))
        #expect(Format.percent(0).hasPrefix("<") == false)
    }

    @Test("Paths are shortened from the middle, keeping both ends")
    func pathElidesTheMiddle() {
        let long = URL(fileURLWithPath: "/a/very/long/path/that/keeps/going/and/going/forever/file.txt")
        let short = Format.path(long, maximumLength: 30)

        #expect(short.count <= 31)
        #expect(short.contains("…"))
        #expect(short.hasPrefix("/a/very"))
        #expect(short.hasSuffix("file.txt"))
    }

    @Test("A short path is left alone")
    func shortPathsAreUntouched() {
        #expect(Format.path(URL(fileURLWithPath: "/tmp/a"), maximumLength: 40) == "/tmp/a")
    }

    @Test("The home folder is abbreviated the way the shell does")
    func pathAbbreviatesHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(Format.path(home.appending(path: "Documents")) == "~/Documents")
    }
}
