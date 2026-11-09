# OpenPhotoCleaner

Sort your photo library fast: one decision per photo, with a swipe on iPhone or the
arrow keys on Mac and iPad. Delete it, keep it, or file it into an album.

Native SwiftUI for iPhone, iPad (iOS 17+) and Mac (macOS 14+). It only uses Apple
frameworks (PhotoKit) and has no third-party dependencies, no ads and no analytics.
Everything happens on your device, in your own Photos library; nothing is uploaded.

> Status: early. The core flow, undo and a small test suite work.

## How it works

| Gesture / key | Action |
|---|---|
| Swipe **right** / `←` / `⌫` | Add to the **delete queue** and go to the next photo |
| Swipe **left** / `→` / `↩` | Keep and go to the next photo |
| Swipe up / `↑` | Save to the target album (asks for one the first time) |
| Swipe down / `↓` / `Esc` | Back to the photo grid |
| `1`–`0` (Mac, iPad) | Save to the album you assigned to that number |
| `A` (`ㅁ`) | Choose the target album |
| `Space` | Toggle Favorite |
| `T` (`ㅅ`) | Rotate 90° clockwise |
| `⌘Z` / shake / ↩ button | Undo (several steps) |

Touch swipes push the card away from the action: the hint you reveal on the opposite side
(Delete on the left, Keep on the right) is the one that runs. Every key has a touch equivalent (buttons under the photo, tappable chips, context
menus), and every action is in the menu bar on Mac and iPad.

- **Nothing is deleted immediately.** Photos go into a delete queue, hidden from the
  flow. You review the queue, restore anything, then delete in one batch. The system
  asks for confirmation, and deleted photos go to *Recently Deleted*.
- **Albums are real Photos albums.** Adding a photo to an album does not copy it, and a
  photo can be in several albums. Tap an album chip on the photo (or press its number
  key again) to take it out of that album.
- **Rotation and favorites are normal Photos edits.** Rotation keeps the original
  (use *Revert* in Photos to undo it); it works for still photos, not Live Photos or video.
- **Resumes where you stopped**, in the card view or in the grid.
- **Mac and iPad share one layout** (black photo background, key hints, numbered-album
  list, keyboard-driven album picker and queue). iPhone keeps the touch-first layout.
- English and Korean. Change the language in the system settings for the app.

## Build and test

Requires a recent Xcode (the project uses Xcode 27's plain-text `project.xcproj`).

```bash
git clone https://github.com/minsikpaul92/OpenPhotoCleaner.git
cd OpenPhotoCleaner
xcodebuild -project OpenPhotoCleaner.xcodeproj -scheme OpenPhotoCleaner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project OpenPhotoCleaner.xcodeproj -scheme OpenPhotoCleaner \
  -destination 'platform=macOS' build
xcodebuild test -project OpenPhotoCleaner.xcodeproj -scheme OpenPhotoCleaner \
  -destination 'platform=macOS'
```

To run on a device, open the project in Xcode, choose your own team under
*Signing & Capabilities* and change the bundle identifier. A free Apple ID is enough.
The app asks for full photo library access on first launch.

## Known limits

- iCloud Shared Photo Library and People have no public API, so the app cannot move
  photos into them. Use a regular album (the app offers a "Pending Share" album) and
  move them in the Photos app.
- The delete confirmation comes from the system and cannot be changed or skipped.
- The delete queue, resume position, number shortcuts and target album are stored
  per device and are not synced. Deleted photos follow iCloud Photos as usual.
- Letter shortcuts work with English and Korean keyboards.

## License

[MIT](LICENSE)
