import Foundation

/// Number and size formatting, in one place so every corner of the UI phrases
/// things the same way.
enum Format {
    /// A size, in the units the Finder uses — so Diskova's "1.2 GB" is the same
    /// 1.2 GB the person sees in Get Info, rather than a different convention
    /// that makes the two disagree.
    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    /// A share of the whole, with a floor so that thousands of tiny files do
    /// not all read as a flat "0%".
    static func percent(_ fraction: Double) -> String {
        guard fraction > 0 else { return 0.0.formatted(.percent.precision(.fractionLength(0))) }
        if fraction < 0.001 {
            return "<" + 0.001.formatted(.percent.precision(.fractionLength(1)))
        }
        let digits = fraction < 0.1 ? 1 : 0
        return fraction.formatted(.percent.precision(.fractionLength(digits)))
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// A duration in seconds, for "scanned in 12.4s".
    static func seconds(_ value: TimeInterval) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + "s"
    }

    /// Shortens a path for display by replacing the home folder with `~` and,
    /// if it is still long, eliding the middle.
    ///
    /// Elides the middle rather than the end because the useful parts of a path
    /// are both ends: which volume it is on, and what the file is called.
    static func path(_ url: URL, maximumLength: Int = 80) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var text = url.path
        if text.hasPrefix(home) {
            text = "~" + text.dropFirst(home.count)
        }
        guard text.count > maximumLength else { return text }

        let keep = (maximumLength - 1) / 2
        return text.prefix(keep) + "…" + text.suffix(keep)
    }
}
