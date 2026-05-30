# NavilIME — Korean Input Method for macOS, Tailored for Emacs Users

## About
- Tested on emacs-plus 30.2, macOS 15.7.4
- Prefers continuous 2-beolsik input, similar to Emacs built-in Korean input method
- Supports Hanja and special character conversion via F9 key

## The Inevitable Struggle of Korean Keyboard Users
- Primarily using MacBook with Emacs/org-mode
- The painful keyboard switching problem between macOS and Emacs is a familiar struggle for Korean users

## Patches
- **ㅆ jongseong fix**: Added `"tt":Jongsung.Ssangsios` — one line fix in `Keyboard002.swift`
- **ㄲ jongseong**: Added `"rr":Jongsung.Ssangkiyeok` for double-tap input
- **Hanja & symbol conversion (F9)**: Press F9 while composing a Korean syllable to open a candidate popup. Select with mouse double-click or arrow keys + Enter. Press F9 again or ESC to dismiss. Powered by a JSON table ported from Emacs `hanja-util.el` (572 entries, covering both Hanja and special symbols). **Lazy loaded** — initialized only on first F9 press, keeping startup lightweight
- **KO/EN status display**: Menu bar dropdown shows 🇰🇷 KO or 🔤 EN to indicate current input mode
- **Emacs multi-key sequence fix**: Modifier key sequences like `C-x p p`, `C-c C-x f` no longer trigger Korean input. Implemented via `commandKeyCount` tracking using `flagsChanged` events — inspired by `(> (length (this-command-keys)) 1)` in Emacs input method API
- **Crash defense**: Added `ensureHangulReady()` to handle cases where macOS calls `handle()` without prior `activateServer()`
- **Lightweight build**: ARM64 only, 2-beolsik only, 3-beolsik layouts removed

## Hanja Conversion — Supported Apps
- Emacs, Upnote, Safari, Chrome, TextEdit and most standard macOS apps
- iTerm2: limited support due to terminal IME constraints

## Options
- **Han/Eng toggle key**: Choose from Shift+Space, Right Command, or Right Option

## Known Limitations
- After a multi-key sequence (e.g. `C-x p p`), Korean input mode must be manually restored via the Han/Eng toggle key
- When in Korean composition state, the first modifier key press (e.g. `C-x`) confirms the current syllable; the shortcut requires a second press to execute

## With the Help of AI
- I am not a developer
- Started this to solve the keyboard switching inconvenience that Korean layout users face
- Fortunately, living in a good era — solved with the help of AI (Claude)

## Build
```bash
cd ~/Project/NavilIMEforMac
rm -rf ~/Library/Developer/Xcode/DerivedData/NavilIME-*
xcodebuild -project NavilIME.xcodeproj \
           -scheme NavilIME \
           -configuration Release \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           ARCHS=arm64 \
           ONLY_ACTIVE_ARCH=NO \
           build 2>&1 | tail -3
```

## Install
```bash
sudo pkill -f NavilIME
cp -r ~/Library/Developer/Xcode/DerivedData/NavilIME-*/Build/Products/Release/NavilIME.app \
      ~/Library/Input\ Methods/
xattr -cr ~/Library/Input\ Methods/NavilIME.app
codesign --force --deep --sign - ~/Library/Input\ Methods/NavilIME.app
open ~/Library/Input\ Methods/NavilIME.app
```

## Credits
- Special thanks to the original author, **navilera**
- https://github.com/navilera/NavilIMEforMac
