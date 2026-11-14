# QuartzHub

*[Deutsch](README.de.md)*

A native macOS app for managing [Quartz 5](https://quartz.jzhao.xyz/) websites: configuration,
plugins, layout, styles, preview and build, publishing, and export as PDF, ePub and offline HTML,
written in Swift.

**Version 1.0.2.** [Download](https://github.com/boxi-os/QuartzHub/releases/latest) the DMG; the
[handbook](https://boxi-os.github.io/QuartzHub/en/) explains every window and page. QuartzHub is not
notarized: the first start needs “Open Anyway” in System Settings ▸ Privacy & Security.

- macOS 26 or later, Apple Silicon
- Brings its own Node.js (for Quartz) and git
- License: GPL-3.0-or-later

## Building

Requires Xcode 27.

```sh
scripts/fetch-runtime.sh   # Node and git into Runtime/ (pinned, checksummed)
scripts/xcodegen.sh        # QuartzHub.xcodeproj from project.yml (XcodeGen, fetched locally)
open QuartzHub.xcodeproj   # or: scripts/package.sh for the app and a DMG
```

QuartzHub is not affiliated with Quartz or its author.
