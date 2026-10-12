# Dustbunny 🐇

A tiny macOS app that sweeps loose screenshots off your Desktop into dated folders every evening, with a little vacuum animation.

```
Desktop/
  Screenshot 2026-10-11 at 18.04.12.png      →   Desktop/Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12.png
  Screenshot 2026-10-10 at 08.00.00.png      →   Desktop/Screenshots/2026-10-10/Screenshot 2026-10-10 at 08.00.00.png
  notes.txt                                  →   (left alone)
```

## Free for anyone to use, fork and change

Dustbunny is free and open source under the [MIT License](LICENSE). **Anyone** may download it, use it, fork it, change it, and share their own version, for personal or commercial use, without asking permission. The only condition is keeping the copyright and license notice in copies of the code.

There is no account, no sign-up, no paid tier, and nothing phones home. Once it's built, it runs entirely on your own Mac.

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/andreasaez/dustbunny/main/install.sh | bash
```

That's it. Dustbunny opens in your Dock and menu bar (look for the 🐇) and asks which folder to tidy (pick your Desktop).

The installer downloads the source code, builds it on your Mac (about a minute), checks the app has exactly Dustbunny's three sandbox permissions, copies it to Applications and opens it. It never uses `sudo` or asks for your password. Because the app is built on your own Mac, macOS opens it without any "unverified developer" warning.

**Requirements:** macOS 14 (Sonoma) or later, and Apple's free developer tools. If you don't have them, the installer tells you to run `xcode-select --install` first.

**Prefer to read the installer before running it?** That's a good habit. Do this instead:

```sh
git clone https://github.com/andreasaez/dustbunny.git
cd dustbunny
less install.sh        # read it
./install.sh
```

To update later, run the same command again. Your settings are kept.

### Fork it

Click **Fork** on GitHub, make whatever changes you like, and install your version with `./install.sh`. If you share your version with other people, please give it your own app identifier, so it doesn't clash with anyone else's copy of Dustbunny:

```sh
BUNDLE_ID=com.yourname.Dustbunny ./scripts/build.sh
```

If you publish your own one-line installer, change the repository address at the top of `install.sh` to your fork.

### Opening a copy someone else built

A Dustbunny build is signed for the Mac it was built on, not with an Apple Developer ID. If you copy a built app to another Mac, macOS will say it can't verify the developer. To open it anyway, go to **System Settings → Privacy & Security** and click **Open Anyway**. Only do this for a copy from someone you trust. Building it yourself avoids the warning entirely.

## Using it

On first launch Dustbunny asks you to choose the folder to tidy (pick your Desktop). After that it lives in your Dock and in the menu bar as a 🐇. Click either one to run a sweep or open Settings.

- **Run Dustbunny Now** (⌘R in the menu) sweeps immediately.
- **Sweep every evening** runs once a day at the time you choose (default 18:00). If your Mac was asleep at that time, it catches up when it wakes the same day.
- **Undo Last Sweep** puts every file from the last sweep back where it was.
- Optional: turn off the animation, open at login.

## Uninstall

1. If you turned on **Open Dustbunny at login**, turn it off in Dustbunny's settings first.
2. Paste this into Terminal:

```sh
osascript -e 'if application id "org.dustbunny.Dustbunny" is running then tell application id "org.dustbunny.Dustbunny" to quit'
rm -rf /Applications/Dustbunny.app ~/Applications/Dustbunny.app
rm -rf ~/Library/Containers/org.dustbunny.Dustbunny
```

The first line quits Dustbunny if it's running. The second deletes the app. The third deletes its saved settings (the folder you chose, your schedule and the undo list). macOS may ask whether Terminal can access data from other apps; click **Allow** so it can delete the settings.

**Your screenshots are not touched.** Anything Dustbunny already sorted stays in its `Screenshots/<date>/` folders. To put files back on the Desktop, use **Undo Last Sweep** before uninstalling, or drag them out yourself.

## Privacy & security

Dustbunny exists to move files around, nothing else. These guarantees come from how the app is built, not just from promises:

| Guarantee | How it's enforced |
|---|---|
| **No network access, in or out** | App Sandbox with no `network.client`/`network.server` entitlement. The kernel blocks every socket. No networking code exists either. |
| **Never reads file contents** | It only lists the folder and matches the *file name* (`Screenshot YYYY-MM-DD at ….png`). The date comes from the name. Files are moved with `renameatx_np(2)`, which never opens them. A test proves this by moving a file that nobody has permission to read. |
| **Touches nothing outside one folder** | The sandbox only grants access to the single folder you pick in the Open panel (`files.user-selected.read-write`). |
| **Never overwrites or deletes** | Moves use `RENAME_EXCL`, so a name clash becomes `… (2).png`. Undo only removes empty day folders. |
| **Can't be redirected** | All work happens through folder handles opened with `O_NOFOLLOW`, so swapping a folder for a symlink, even mid-sweep, can't send files anywhere else. Symlinked screenshots are skipped. |
| **Undo can't be abused** | Undo records store bare file names only, never paths. Each record is re-checked: both names must be screenshot names whose date matches the day folder. |
| **Private folders** | The `Screenshots` and day folders are created `0700` (only you can open them). |
| **No injection points / cross-app surface** | No URL schemes, AppleScript dictionary, Services, XPC, document types, or command-line arguments. The standard "open file", "open URL" and "print" Apple Events are actively refused. Settings are stored in the app's own sandboxed preferences. |
| **No supply chain** | Zero third-party dependencies, only Apple frameworks. |
| **No tracking** | No analytics, telemetry, or crash reporting. A privacy manifest (`PrivacyInfo.xcprivacy`) declares no collected data. |

The file-handling logic lives in [`Sources/DustbunnyCore`](Sources/DustbunnyCore) (about 300 lines). Unit tests cover the symlink, symlink-swap, overwrite, unreadable-file and undo-tampering cases, plus 20,000 fuzzed file names.

One honest caveat: if your Desktop syncs to iCloud, macOS uploads the moved files the same way it uploads any change you make. That is the system's sync, not Dustbunny; the app itself has no network access.

You can check the permissions of any build yourself:

```sh
codesign -d --entitlements - /Applications/Dustbunny.app
```

It should list exactly three: `app-sandbox`, `files.user-selected.read-write` and `files.bookmarks.app-scope`. Anything else means the build isn't the one from this repository.

## Your data stays on your Mac

Dustbunny keeps nothing about you anywhere except your own Mac, and even there it keeps very little:

- **Its settings** (the folder you chose, the schedule time, the toggles) are kept in the app's private sandbox folder, `~/Library/Containers/org.dustbunny.Dustbunny`. No other app can read them, and they never leave your Mac.
- **The undo list** is the file names from the last sweep, so they can be put back. It's cleared when you undo or choose a different folder.
- There are **no accounts, IDs, analytics, logs or crash reporters**. Nobody, including the authors, can see that you use Dustbunny, how often, or what it moved.
- **Building it** reads no environment variables except the optional `SIGN_IDENTITY` and `BUNDLE_ID` described below. Nothing about your machine is written into the app.

To remove every trace, follow the [Uninstall](#uninstall) steps.

## Development

```sh
swift test                # run the unit tests
./scripts/build.sh        # build build/Dustbunny.app (universal, sandboxed, hardened runtime)
```

The app icon is drawn in code by [`scripts/make-icon.swift`](scripts/make-icon.swift), with no external images. To change it, edit the script and regenerate `Resources/AppIcon.icns`:

```sh
swiftc -parse-as-library -o /tmp/make-icon scripts/make-icon.swift && /tmp/make-icon
```

To sign a build for distribution with your own Apple Developer ID (then notarize it with `xcrun notarytool`):

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
```

Pull requests are welcome. Changes that add network access, new entitlements, third-party dependencies, or anything that reads file contents won't be accepted into this repository, though you're free to do whatever you like in your own fork.

If you find a security problem, please report it privately through the repository's **Security** tab rather than opening a public issue.

## Notes

- Matches the English macOS screenshot names (`Screenshot …`, `Screen Shot …`). Screenshots saved under a custom name or a non-English system name are left alone.
- Respects **Reduce Motion**: the animation becomes a still image.

## License

[MIT](LICENSE). Free to use, copy, modify and share.
