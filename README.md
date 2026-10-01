# Storage Cleaner

A small SwiftUI macOS app for freeing up disk space. It has two modes:

- **Big Files** — recursively scans a folder you choose and lists the largest files it finds, so you can quickly spot and remove the ones eating your storage.
- **Small File Clutter** — scans well-known clutter locations that quietly add up: `~/Library/Caches`, `~/Library/Logs`, Xcode DerivedData, iOS Simulator caches, stray `.DS_Store` files, the Trash, and Downloads untouched for 90+ days.

In both modes you select files/categories with checkboxes and click **Move to Trash** — deletions go to the Trash, not permanent removal, so they're reversible.

## Requirements

- macOS 14+
- Swift 5.9+ (Xcode or Swift toolchain installed)

## Run

```bash
swift run
```

## Build a release binary

```bash
swift build -c release
```

The binary will be at `.build/release/StorageCleaner`.
