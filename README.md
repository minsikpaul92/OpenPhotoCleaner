# OpenPhotoCleaner

Sort your photo library fast, with a swipe on iPhone or the arrow keys on Mac.
Each photo is one decision: delete it, keep it, or file it into an album.

Native SwiftUI for iPhone (iOS 17+) and Mac (macOS 14+). It only uses Apple
frameworks (PhotoKit) and has no third-party dependencies. Everything happens on
your device, in your own Photos library; nothing is uploaded.

> Status: early. The core flow works; undo and a test suite are not done yet.

## How it works

| Gesture / key | Action |
|---|---|
| Swipe left / `←` | Add to the **delete queue** and go to the next photo |
| Swipe right / `→` | Keep and go to the next photo |
| Swipe up / `↑` | Save to the target album (asks for one the first time) |
| Swipe down / `↓` | Back to the photo grid |

- **Nothing is deleted immediately.** Photos go into a delete queue, hidden from
  the flow. You review the queue, restore anything, then delete in one batch.
  The system asks for confirmation, and deleted photos go to
  *Recently Deleted*.
- **Albums are real Photos albums.** Adding a photo to an album does not copy it,
  and a photo can be in several albums. Tap an album chip on the photo (or press
  its number key again on Mac) to take it out of that album.
- **Resumes where you stopped**, in the card view or in the grid.
- Mac extras: number keys `1`–`0` file the photo into the album you assigned to
  that number, `↑↑` opens the album picker, `Esc` goes back to the grid, and the
  album picker and queue are fully keyboard driven.
- English and Korean. Change the language in the system settings for the app.

## Build

Requires a recent Xcode (the project uses Xcode 27's plain-text `project.xcproj`).

```bash
git clone https://github.com/minsikpaul92/OpenPhotoCleaner.git
cd OpenPhotoCleaner
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe \
  -destination 'platform=macOS' build
```

The Xcode project and target are still named `PhotoSwipe`. To run on a device,
open the project in Xcode, choose your own team under *Signing & Capabilities*
and change the bundle identifier. A free Apple ID is enough. The app asks for
full photo library access on first launch.

## Known limits

- iCloud Shared Photo Library and People have no public API, so the app cannot
  move photos into them. Use a regular album (the app offers a "Pending Share"
  album) and move them in the Photos app.
- The delete confirmation comes from the system and cannot be changed or skipped.

## License

[MIT](LICENSE)
