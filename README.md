# Ice Bear Look Away

A small macOS menu bar app for the 20-20-20 break: every 20 minutes, Ice Bear appears and asks you to look about 20 feet away for 20 seconds. The reminder has a countdown, a **Done** button, and a **Restart 20 seconds** button.

The menu bar bear lets you **Pause reminders** and **Resume reminders**. Your pause choice is remembered across restarts. You can also choose **Show reminder now** to try it immediately. If you connect Google Calendar, reminders pause during busy times on your primary calendar and restart their 20-minute interval after the meeting.

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

To stop and remove the app, its login item, and any saved Google Calendar connection, run `./scripts/uninstall.sh` from the cloned repository.

## Connect Google Calendar (optional)

The app checks only free/busy availability on your Google Calendar. It does not read meeting titles, guests, or descriptions. This connection is separate from macOS Calendar and requires no calendar sync in System Settings.

Each person installing the app needs a Google OAuth **Desktop app** client ID:

1. In [Google Cloud Console](https://console.cloud.google.com/), create or choose a project. Enable the [Google Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com).
2. In [Google Auth Platform](https://console.cloud.google.com/auth/overview), configure the OAuth consent screen. Choose **External** if you use a personal Google account. While the app is in testing, add your Google account under **Test users**. Add the `https://www.googleapis.com/auth/calendar.freebusy` scope.
3. Under **Clients**, create an OAuth client with application type **Desktop app**. Copy its **Client ID** (ending in `.apps.googleusercontent.com`). You do not need to put its client secret in this app.
4. Open Ice Bear from the menu bar, choose **Connect Google Calendar…**, paste the client ID, and finish sign-in in your regular browser.

The app stores the refresh token in your Mac Keychain and checks your primary calendar every 30 seconds and again before showing a reminder. If it cannot check your calendar, it holds reminders until the connection recovers; the menu bar shows the error. **Disconnect Google Calendar** removes the saved token and returns to ordinary 20-minute reminders. Manual **Pause reminders** still takes priority. **Show reminder now** always opens a reminder when you choose it.

For a shared app with one client ID, the owner would need to configure the Google OAuth app for other users and satisfy any Google verification requirements. Using your own Desktop app client ID avoids relying on someone else's Google Cloud project.

Google refresh tokens from an **External** OAuth app in **Testing** mode expire after seven days. If the menu shows that it cannot check availability after a week, choose **Change Google Calendar connection…** and sign in again. Publishing your OAuth app changes that token lifetime, subject to Google's requirements.

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
