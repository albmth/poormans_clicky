# Clicky Quick Guide

Simple commands and steps to open, start, and use the app.

## 1. Open the App Project

From the project root:

```bash
open leanring-buddy.xcodeproj
```

Use Xcode to build and run the app.

Do not run `xcodebuild` from the terminal because it can invalidate macOS privacy permissions for this app.

## 2. Start the App

In Xcode:

1. Select the `leanring-buddy` scheme.
2. Select your Mac as the run destination.
3. Set a signing team if Xcode asks for one.
4. Press `Cmd + R`.

The app has no dock icon and no normal main window.

It runs from the macOS menu bar.

## 3. Open the App Panel

After the app starts:

1. Look for the Clicky icon in the macOS menu bar.
2. Click the menu bar icon.
3. The floating control panel should open.

Click outside the panel to close it.

## 4. Grant Permissions

The app may ask for these macOS permissions:

- Microphone
- Screen Recording
- Accessibility

Grant the requested permissions in System Settings.

If macOS asks you to restart the app after changing permissions, quit the app and run it again from Xcode.

## 5. Use Voice Input

Hold:

```text
Control + Option
```

Speak while holding the keys.

Release the keys to send the request.

The app captures your voice, includes screen context, and shows the assistant response near the cursor.

## 6. Quit the App

Open the menu bar panel and use the quit button.

You can also stop the app from Xcode with:

```text
Cmd + .
```

## Optional: Run the Worker Locally

Only use this if you are working on the Cloudflare Worker proxy.

```bash
cd worker
npm install
npx wrangler dev
```

For deployment:

```bash
cd worker
npx wrangler deploy
```

Worker secrets are required for real API-backed transcription, chat, and text-to-speech.

