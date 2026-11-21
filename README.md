# Nephele

A native macOS 26 app for managing a Cloudflare account: domains, DNS, alerts and usage (Workers, storage and Zero Trust to follow). Pure Swift and SwiftUI. Independent project, not affiliated with Cloudflare.

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
swift test --package-path Packages/CloudflareKit
xcodebuild test -scheme Nephele -destination 'platform=macOS'
```

Licence: MIT.
