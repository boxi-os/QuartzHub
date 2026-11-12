# QuartzHub

*[Deutsch](README.de.md)*

A native macOS app for managing [Quartz 5](https://quartz.jzhao.xyz/) websites: configuration,
plugins, layout, styles, preview and build, publishing, and export as PDF, ePub and offline HTML.
QuartzHub is the successor of [QuartzControl](https://github.com/boxi-os/QuartzControl) (Electron),
written in Swift, and reads the same projects.

**Status:** in development, not released. The first release comes when QuartzHub can do everything
QuartzControl 1.3 does. Until then, use QuartzControl.

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
