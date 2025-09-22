Dial 9 Call History iOS App
A simple yet powerful iOS application built with SwiftUI to browse, play, download, and manage call recordings from the Dial 9 API.

Description
This app provides a user-friendly interface for interacting with the Dial9 v2 API. Users can securely enter their API credentials, select a date, and view a list of all call recordings. From there, they can play back recordings with a scrubber, download them as .wav files to their device, or permanently delete them from the server.

The app is built as a single-file SwiftUI project, making it easy to understand, modify, and integrate into an existing Xcode project.

Features
Secure Credential Storage: API credentials (X-Auth-Token & X-Auth-Secret) are saved securely in the iOS Keychain. Users can opt-in or out of saving their details.

Fetch by Date: Use the date picker to retrieve a complete list of call logs for any specific day.

In-App Audio Playback: Play call recordings directly within the app.

Playback Scrubber: A dynamic progress bar appears for the currently playing recording, allowing you to scrub to any point in the call.

Download Recordings: Save recordings to your device's Files app as standard .wav files.

Delete Recordings: Permanently delete recordings from the Dial 9 server with a confirmation dialog to prevent accidents.

Clear UI Feedback: The interface provides visual cues for incoming/outgoing calls, loading states, playback status, and error messages.

How It Works
The app is built entirely in SwiftUI and uses several native iOS frameworks to achieve its functionality:

Networking: It uses URLSession to make secure POST requests to the Dial 9 API endpoints (/logs/search and /logs/recording).

Data Handling: The app correctly parses the JSON responses from the API, including the Base64 encoded audio data for recordings.

Audio Processing: Since the API provides raw audio data, the app programmatically constructs a valid .wav file header before saving or playing the recording. This ensures compatibility with iOS audio players.

Security: The Security framework is used to interact with the iOS Keychain for saving and retrieving API credentials securely.

File Management: SwiftUI's .fileExporter is used to present a native "Save" sheet for downloading the .wav files.

Setup
Open in Xcode: Place the Dial9DownloaderView.swift file into a new or existing iOS App project in Xcode.

Build & Run: Build the project and run it on an iOS Simulator or a physical device.

Enter Credentials:

Tap the info icon for instructions on where to find your API keys.

Enter your X-Auth-Token and X-Auth-Secret.

Check the "Save Details" box to have the app securely remember your credentials for next time.

Fetch & Play: Select a date and tap "Fetch Recordings" to view the call history.

