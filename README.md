# Educazam

Educazam is a small iOS app for listening to Rádio Educativa Campinas and quickly identifying the song currently playing with the Shazam shortcut on the device.

## What it does

- Streams Rádio Educativa Campinas from `https://streaming.ima.sp.gov.br/educativa.mp3`.
- Starts radio playback muted and lets you mute or unmute it from the app.
- Supports background audio playback and exposes playback information and controls through iOS Now Playing.
- Opens the Shortcuts app to run a shortcut named **Atalho do Shazam**.

Song recognition is handled by the Shazam shortcut. Educazam does not analyze or transcribe the audio itself.

## Run in Xcode

1. Open `Educazam.xcodeproj` in Xcode.
2. Select the Educazam scheme and an iPhone or iPad destination.
3. Choose your development team in Signing & Capabilities if Xcode requests it.
4. Build and run the app.

To use the Shazam button, create or install a Shortcut named **Atalho do Shazam** in the Shortcuts app.

## Built with

- SwiftUI
- AVFoundation for radio streaming and audio playback
- MediaPlayer for Now Playing metadata and remote playback controls
