#!/bin/bash
# Dustbunny installer: downloads the source, builds it on this Mac, and installs Dustbunny.app.
#
#   curl -fsSL https://raw.githubusercontent.com/andreasaez/dustbunny/main/install.sh | bash
#
# Or, from a copy of the repository:  ./install.sh
#
# What it does, and nothing else:
#   1. Checks for macOS 14+ and Apple's developer tools.
#   2. Uses the repository it's run from, or downloads the latest source with git into a temporary folder.
#   3. Builds the app with scripts/build.sh and checks it has exactly Dustbunny's three sandbox permissions.
#   4. Copies it to /Applications (or ~/Applications if that isn't writable) and opens it.
# It never uses sudo, never asks for your password, and deletes its temporary folder when done.
#
# Optional: DUSTBUNNY_INSTALL_DIR=/some/folder to install somewhere else.

# Everything runs inside main(), called on the last line, so a partially downloaded script does nothing.
work_dir=""

main() {
    set -euo pipefail

    # Forks: point this at your own repository.
    local repo="https://github.com/andreasaez/dustbunny.git"
    local bundle_id="org.dustbunny.Dustbunny"

    say() { printf '\033[1;35m🐇 %s\033[0m\n' "$*"; }
    fail() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

    # 1. Requirements
    [[ "$(uname -s)" == "Darwin" ]] || fail "Dustbunny is a macOS app."
    local major
    major="$(sw_vers -productVersion | cut -d. -f1)"
    (( major >= 14 )) || fail "Dustbunny needs macOS 14 (Sonoma) or later."
    if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
        fail "Apple's developer tools are needed to build Dustbunny. Run:  xcode-select --install   then run this installer again."
    fi

    # 2. Source: this repository if we're inside one, otherwise a fresh download.
    local source_dir
    local script_dir=""
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    if [[ -n "$script_dir" && -f "$script_dir/Package.swift" && -f "$script_dir/scripts/build.sh" ]]; then
        source_dir="$script_dir"
        say "Building from $source_dir"
    else
        command -v git >/dev/null 2>&1 || fail "git is needed. Run:  xcode-select --install"
        work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dustbunny-install.XXXXXX")"
        # work_dir is global (not local) so this cleanup still sees it after main() returns.
        trap 'rm -rf "$work_dir"' EXIT
        say "Downloading Dustbunny…"
        git clone --quiet --depth 1 "$repo" "$work_dir/dustbunny" || fail "Couldn't download $repo"
        source_dir="$work_dir/dustbunny"
    fi

    # 3. Build and verify
    say "Building (this takes about a minute)…"
    local log="${work_dir:-${TMPDIR:-/tmp}}/dustbunny-build.log"
    if ! "$source_dir/scripts/build.sh" >"$log" 2>&1; then
        tail -20 "$log" >&2
        fail "The build failed (full log: $log)"
    fi
    local built="$source_dir/build/Dustbunny.app"
    [[ -d "$built" ]] || fail "The build didn't produce Dustbunny.app"

    local entitlements
    entitlements="$(codesign -d --entitlements - --xml "$built" 2>/dev/null)"
    local key count=0
    for key in com.apple.security.app-sandbox com.apple.security.files.user-selected.read-write com.apple.security.files.bookmarks.app-scope; do
        [[ "$entitlements" == *"<key>$key</key>"* ]] || fail "Built app is missing the expected permission $key; not installing."
    done
    count="$(grep -o '<key>' <<<"$entitlements" | wc -l | tr -d ' ')"
    [[ "$count" == "3" ]] || fail "Built app has $count permissions instead of 3; not installing."
    codesign --verify --strict "$built" || fail "Built app's signature didn't verify; not installing."

    # 4. Install
    local dest="${DUSTBUNNY_INSTALL_DIR:-}"
    if [[ -z "$dest" ]]; then
        if [[ -w /Applications ]]; then dest="/Applications"; else dest="$HOME/Applications"; fi
    fi
    mkdir -p "$dest"
    local target="$dest/Dustbunny.app"

    # Quit a running copy first (checking first, because "tell application" would launch it otherwise).
    osascript -e "if application id \"$bundle_id\" is running then tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "/Dustbunny.app/Contents/MacOS/Dustbunny" >/dev/null || break
        sleep 0.5
    done

    if [[ -e "$target" ]]; then
        [[ -d "$target/Contents" && "$(basename "$target")" == "Dustbunny.app" ]] || fail "$target exists but isn't Dustbunny; leaving it alone."
        rm -rf "$target"
    fi
    ditto "$built" "$target"
    say "Installed to $target"

    open "$target"
    say "Done! Dustbunny is in your Dock and menu bar (🐇). Choose the folder to tidy."
}

main "$@"
