# Contributing to Diskova

Pull requests are welcome, including small ones. If you are unsure whether an
idea fits, open an issue first and ask — that is cheaper for both of us than a
rejected branch.

## Getting set up

```bash
git clone https://github.com/erenahmettt/diskova.git && cd diskova && open Diskova.xcodeproj
```

No account, no signing certificate, no dependencies. The project builds and
runs ad-hoc signed.

```bash
xcodebuild -scheme Diskova -destination 'platform=macOS' test
```

CI runs exactly that on every push and pull request.

## Good first issues

These are real jobs, roughly easiest first:

1. **More file extensions.** `FileKind.extensionIndex` in
   `Diskova/Model/FileKind.swift` is a flat table. Add the formats your field
   uses — CAD, bioinformatics, game engines, music production — with a test case
   in `FileKindTests`.
2. **More build and cache folder names.** Same file,
   `buildAndCacheDirectoryNames`. If your toolchain dumps gigabytes somewhere
   predictable, Diskova should colour it as reclaimable.
3. **Another language.** `Diskova/Resources/Localizable.xcstrings` already has
   English and Turkish. Adding a language is one more entry per string, plus
   the language code in the project's known regions.
4. **Quick Look on the space bar.** Needs a `QLPreviewPanel` data source wired
   into the responder chain, which SwiftUI makes awkward — a genuinely
   interesting piece of AppKit plumbing.
5. **Filter by category.** Clicking a legend entry should dim everything else.
   The layout already knows each tile's kind.
6. **Scan comparison.** Save an outcome, scan again later, show what grew. The
   tree is `Codable`-shaped already; the interesting part is the diff.

## House style

- **Swift 6 language mode, strict concurrency, no warnings.** The build is
  warning-free today; please keep it that way.
- **Comments explain why, not what.** `// increment the counter` above
  `counter += 1` is noise. The reason a folder is skipped, or why a size is
  allocated rather than logical, is not.
- **Logic goes in testable types.** The scanner and the treemap layout are plain
  Swift with no SwiftUI import, which is what lets them be tested properly.
  Please keep views thin.
- **New behaviour comes with a test.** Scanner tests build real temporary
  directories rather than mocking the filesystem — the whole point of that code
  is how it behaves against a real APFS volume.
- **Nothing is deleted outright.** Any new destructive action goes through the
  Trash and asks first. This is not negotiable; people run this app on their
  only copy of their photos.

## Changing the colours

Do not eyeball a palette. The numbers in the README's accessibility table were
measured, and a change that lowers them is a regression even if it looks nicer.
If you want to propose different hues, include the measured worst-pair figures
for normal vision and for protanopia, deuteranopia and tritanopia, in both light
and dark mode, and say what tool produced them.

## Commits and pull requests

- One logical change per pull request.
- Write commit subjects in the imperative: "Skip symlinks when scanning".
- Say in the description what a reviewer should look at hardest.
