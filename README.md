# Ice Bear Look Away

A small macOS menu bar app for the 20-20-20 break: every 20 minutes, Ice Bear appears and asks you to look about 20 feet away for 20 seconds. The reminder has a countdown, a **Done** button, and a **Restart 20 seconds** button.

The menu bar bear lets you **Pause reminders** before a meeting and **Resume reminders** afterward. Your pause choice is remembered across restarts. You can also choose **Show reminder now** to try it immediately.

## Set up

You need a Mac, an internet connection for the first build, and Apple's Xcode Command Line Tools. If the tools are missing, run `xcode-select --install` and finish Apple's installer.

```bash
git clone https://github.com/rachelxiao907/ice-bear-look-away.git
cd ice-bear-look-away
./scripts/install.sh
```

The installer builds the app in `build/`, puts it in `~/Applications`, starts it, and sets it to start when you log in. Find the bear icon in the macOS menu bar. You may need to make room for it if your menu bar is crowded.

To install the app somewhere else, set `INSTALL_DIR`:

```bash
INSTALL_DIR="$HOME/Desktop" ./scripts/install.sh
```

To stop and remove the app and its login item, run `./scripts/uninstall.sh` from the cloned repository.

## Sound

When Slack is installed at `/Applications/Slack.app`, reminders play Slack's local `knock_brush` notification sound. Otherwise, they play the macOS Glass sound. Slack's audio file is read from your own installation; it is not included in this repository or copied into the app.

## Image

The build downloads [this Ice Bear thumbnail](https://i.ytimg.com/vi/j5HZudOrLqk/maxresdefault.jpg), crops out the lower-left logo, and uses a centered, tall crop that shows Ice Bear and all of the axe visible in the source thumbnail. The app icon uses a tighter crop. The image is from *We Bare Bears* and is not included in the repository. No show image is committed to this repository.

To build with a JPG already on your computer, use `BEAR_IMAGE`:

```bash
BEAR_IMAGE="/path/to/your-image.jpg" ./scripts/install.sh
```

## Build without installing

Run `./scripts/build.sh`. The finished app is `build/Ice Bear Reminder.app`.

*We Bare Bears*, Ice Bear, the thumbnail, and Slack are owned by their respective rights holders. This is an independent fan project.
