import Foundation

/// The broad category an entry falls into.
///
/// Categories exist to answer one question at a glance: *what sort of thing is
/// filling up this disk?* They are deliberately few. A legend with thirty
/// colours tells you nothing, and the treemap has to stay readable at a glance,
/// so related formats are grouped rather than split (a `.dmg` and a `.zip` are
/// both "archive"; a `.mov` and an `.mkv` are both "video").
enum FileKind: String, CaseIterable, Sendable, Codable {
    /// A folder whose contents are shown. Never used for files.
    case folder
    /// Apps and other bundles presented as a single item.
    case application
    case image
    case video
    case audio
    /// Text documents, PDFs, spreadsheets, presentations, ebooks.
    case document
    /// Compressed archives, installers and disk images.
    case archive
    /// Source code, project files, and the structured data that lives beside
    /// it: databases, configuration, logs, fonts, binaries, models, VM images.
    ///
    /// Code and data share one category because the palette has room for eight
    /// hues and splitting them would cost a hue that media and documents need
    /// more — see `FileKind+Appearance.swift` for the measurements behind that.
    case code
    /// Build output and caches — the stuff that regenerates itself. Diskova
    /// highlights these separately because they are usually the single safest
    /// thing to delete on a developer's machine.
    case developer
    /// Anything unrecognised.
    case other

    /// Short label for the legend and the inspector.
    var displayName: LocalizedStringResource {
        switch self {
        case .folder: "Folders"
        case .application: "Apps"
        case .image: "Images"
        case .video: "Video"
        case .audio: "Audio"
        case .document: "Documents"
        case .archive: "Archives"
        case .code: "Code & data"
        case .developer: "Build & cache"
        case .other: "Other"
        }
    }

    /// SF Symbol shown next to the label.
    var symbolName: String {
        switch self {
        case .folder: "folder.fill"
        case .application: "app.fill"
        case .image: "photo.fill"
        case .video: "film.fill"
        case .audio: "music.note"
        case .document: "doc.fill"
        case .archive: "shippingbox.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .developer: "hammer.fill"
        case .other: "questionmark.square.dashed"
        }
    }

    /// Whether deleting entries of this kind is usually safe and reversible
    /// without losing anything the person actually made.
    ///
    /// Used only to add a gentle note in the inspector — Diskova never acts on
    /// this by itself and never pre-selects anything for deletion.
    var isUsuallyReclaimable: Bool {
        self == .developer
    }

    /// Order the legend and the summary use, so the colours always appear in
    /// the same sequence no matter what a particular disk happens to contain.
    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

extension FileKind {
    /// Classifies a file by its path extension.
    ///
    /// Extension-based classification is wrong occasionally and that is fine:
    /// the alternative is reading the beginning of every file on the disk,
    /// which would turn a thirty-second scan into a ten-minute one for a
    /// prettier legend. Uniform type identifiers are not used either, because
    /// resolving them per file is itself slow on large trees.
    static func forFile(named name: String) -> FileKind {
        let fileExtension = (name as NSString).pathExtension.lowercased()
        if fileExtension.isEmpty {
            // Dotfiles like `.zshrc` have no extension but are plainly config.
            return name.hasPrefix(".") ? .code : .other
        }
        return extensionIndex[fileExtension] ?? .other
    }

    /// Classifies a folder by name, so caches and build output stand out.
    ///
    /// Only names that are unambiguous conventions are listed. `build`, `dist`
    /// and `target` are included despite being ordinary English words, because
    /// in practice a folder with one of those names is build output far more
    /// often than not — and misclassifying it only changes its colour.
    static func forDirectory(named name: String) -> FileKind {
        buildAndCacheDirectoryNames.contains(name.lowercased()) ? .developer : .folder
    }

    /// Folder names that hold regenerable build output or caches.
    static let buildAndCacheDirectoryNames: Set<String> = [
        "node_modules", "bower_components", "jspm_packages",
        "deriveddata", "build", "dist", "out", "target", "_build",
        "caches", "cache", ".cache", "cachedata",
        "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox",
        ".venv", "venv", "virtualenv",
        ".gradle", ".m2", ".ivy2", ".sbt",
        ".cargo", ".rustup",
        ".pub-cache", ".dart_tool",
        ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".vite",
        ".swiftpm", ".build", "pods", "carthage",
        "zz_archive", "logs",
    ]

    /// Extension to category. Flat lookup table, built once.
    private static let extensionIndex: [String: FileKind] = {
        var index: [String: FileKind] = [:]
        func add(_ kind: FileKind, _ extensions: [String]) {
            for item in extensions { index[item] = kind }
        }

        add(.application, [
            "app", "appex", "xpc", "framework", "bundle", "plugin", "kext", "prefpane", "qlgenerator",
        ])
        add(.image, [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg",
            "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "psd", "ai", "eps", "icns",
            "ico", "avif", "jxl", "exr", "hdr", "sketch", "fig", "xcf", "afphoto", "afdesign",
        ])
        add(.video, [
            "mov", "mp4", "m4v", "avi", "mkv", "webm", "flv", "wmv", "mpg", "mpeg", "mts", "m2ts",
            "3gp", "prproj", "fcpbundle", "braw", "r3d", "vob", "ogv", "dv",
        ])
        add(.audio, [
            "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma", "alac",
            "mid", "midi", "logicx", "band", "aup3", "caf", "au", "ape",
        ])
        add(.document, [
            "pdf", "doc", "docx", "odt", "rtf", "txt", "md", "markdown", "pages", "tex",
            "xls", "xlsx", "ods", "numbers", "csv", "tsv",
            "ppt", "pptx", "odp", "key", "epub", "mobi", "azw3", "djvu", "chm", "xps",
        ])
        add(.archive, [
            "zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "7z", "rar", "lz", "lzma",
            "dmg", "iso", "pkg", "mpkg", "cdr", "sparseimage", "sparsebundle", "img",
            "jar", "war", "apk", "ipa", "deb", "rpm", "msi", "exe", "cab", "aar", "xip",
        ])
        add(.code, [
            "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "rs", "go", "java", "kt", "kts",
            "py", "rb", "php", "pl", "lua", "sh", "bash", "zsh", "fish", "ps1", "bat",
            "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue", "svelte", "dart", "scala", "clj", "ex", "exs",
            "erl", "hs", "ml", "fs", "cs", "vb", "r", "jl", "nim", "zig", "v", "sol",
            "html", "htm", "css", "scss", "sass", "less", "styl",
            "xcodeproj", "xcworkspace", "pbxproj", "sln", "csproj", "gradle", "cmake",
            "ipynb", "rmd", "patch", "diff", "lock",
        ])
        add(.developer, [
            "o", "a", "obj", "lib", "pyc", "pyo", "class", "dex", "wasm", "bc", "pch", "gch",
            "dsym", "xcarchive", "swiftmodule", "swiftdoc", "swiftsourceinfo", "tbd", "modulemap",
            "ccache", "incremental",
        ])
        add(.code, [
            "sqlite", "sqlite3", "db", "db3", "realm", "mdb", "accdb", "sql", "dump",
            "json", "yaml", "yml", "toml", "xml", "plist", "ini", "conf", "cfg", "env", "properties",
            "log", "pcap", "parquet", "avro", "arrow", "feather", "hdf5", "h5", "npy", "npz",
            "bin", "dat", "dylib", "so", "dll", "node",
            "ttf", "otf", "woff", "woff2", "eot", "ttc", "dfont",
            "gguf", "safetensors", "onnx", "pt", "pth", "ckpt", "mlmodel", "mlpackage", "tflite",
            "vmdk", "vdi", "qcow2", "utm", "pvm", "vbox",
        ])

        return index
    }()
}
