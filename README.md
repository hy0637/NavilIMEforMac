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
- **Emacs integration**: When Emacs gains focus, NavilIME automatically switches the system input source to ABC, completely yielding control to Emacs. Korean input inside Emacs is handled by the user's Emacs configuration (e.g. `hy-hangul.el`). This eliminates all modifier key sequence conflicts (`C-x p p`, `C-c C-x f`, etc.)
- **First character bug fix**: Added `setValue(_:forTag:client:)` + `overrideKeyboard` workaround inspired by Gureum IME, resolving the occasional first-character failure after focus switch
- **Crash defense**: Added `ensureHangulReady()` to handle cases where macOS calls `handle()` without prior `activateServer()`
- **Lightweight build**: ARM64 only, 2-beolsik only, 3-beolsik layouts removed

## Hanja Conversion — Supported Apps
- Upnote, Safari, Chrome, TextEdit and most standard macOS apps
- iTerm2: limited support due to terminal IME constraints

## Options
- **Han/Eng toggle key**: Choose from Shift+Space, Right Command, or Right Option

## Emacs Usage
NavilIME automatically steps aside when Emacs is active — no configuration needed.
Korean input inside Emacs is entirely up to your Emacs setup.
Recommended: use a built-in Emacs Korean input method such as `hy-hangul.el` or `korean-hangul`.

## Known Limitations
- First character input after focus switch may occasionally fail (rare, Apple IMKit bug). Partially mitigated via `overrideKeyboard` workaround
- `overrideKeyboard` is hardcoded to `com.apple.keylayout.ABC`. Users with non-ABC keyboard layouts (Dvorak, Colemak, etc.) should modify this value in `NavilIMEInputController.swift`

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
