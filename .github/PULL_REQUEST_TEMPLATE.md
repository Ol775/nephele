## What and why

## How I checked it
- [ ] `swift test --package-path Packages/CloudflareKit` and `xcodebuild test -scheme Nephele` pass
- [ ] New behaviour has a test; destructive actions confirm; secrets stay out of logs and errors
- [ ] Ran the app (`--demo` is fine) in Light and Dark
- [ ] No tokens or real account data in screenshots or logs
- [ ] CHANGELOG.md updated
