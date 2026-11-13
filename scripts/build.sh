#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$repo_dir/build"
app_dir="$build_dir/Ice Bear Reminder.app"
resources_dir="$app_dir/Contents/Resources"
image_url="https://i.ytimg.com/vi/j5HZudOrLqk/maxresdefault.jpg"
image_sha256="f5210790fc8677b4c63383462c2711a146807e67f50f66925ece93f6a430f9ab"

command -v swiftc >/dev/null || { echo "Install Xcode Command Line Tools: xcode-select --install" >&2; exit 1; }
command -v sips >/dev/null || { echo "macOS sips is required" >&2; exit 1; }
mkdir -p "$resources_dir" "$build_dir/icons"
mkdir -p "$build_dir/module-cache"

if [[ -n "${BEAR_IMAGE:-}" ]]; then
	cp "$BEAR_IMAGE" "$resources_dir/BearImage.jpg"
else
	curl --fail --location --silent --show-error "$image_url" --output "$resources_dir/BearImage.jpg"
	actual_sha256="$(shasum -a 256 "$resources_dir/BearImage.jpg" | cut -d ' ' -f 1)"
	if [[ "$actual_sha256" != "$image_sha256" ]]; then
		echo "The source image changed. Set BEAR_IMAGE to a local JPG to continue." >&2
		exit 1
	fi
fi

swift -module-cache-path "$build_dir/module-cache" "$repo_dir/scripts/make-icon.swift" "$resources_dir/BearImage.jpg" "$resources_dir/AppIcon.png"
swift -module-cache-path "$build_dir/module-cache" "$repo_dir/scripts/make-popup-image.swift" "$resources_dir/BearImage.jpg" "$resources_dir/PopupBear.png"
for size in 16 32 64 128 256 512 1024; do
	sips --resampleHeightWidth "$size" "$size" "$resources_dir/AppIcon.png" --out "$build_dir/icons/icon-$size.png" >/dev/null
done
python3 "$repo_dir/scripts/create-icns.py" "$build_dir/icons" "$resources_dir/AppIcon.icns"

mkdir -p "$app_dir/Contents/MacOS"
swiftc -O -module-cache-path "$build_dir/module-cache" "$repo_dir/Sources/IceBearReminder.swift" -o "$app_dir/Contents/MacOS/IceBearReminder"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>IceBearReminder</string>
<key>CFBundleIdentifier</key><string>com.rachel.ice-bear-reminder</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleName</key><string>Ice Bear Reminder</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir" >/dev/null
echo "Built $app_dir"
