import SwiftUI
import Combine
import AVKit // Required for audio playback
import UniformTypeIdentifiers // Required for file exporting
import Security // Required for Keychain access

// MARK: - APP ENTRY POINT
@main
struct Dial9DownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            Dial9DownloaderView()
        }
    }
}

// MARK: - KEYCHAIN HELPER
/// A helper class to securely save, read, and delete data from the iOS Keychain.
class KeychainHelper {
    
    static let standard = KeychainHelper()
    // Updated service name to match the new app name for consistency.
    private let service = "com.dial9.callhistory"

    private init() {}

    /// Saves a string securely to the Keychain.
    func save(_ string: String, for account: String) {
        guard let data = string.data(using: .utf8) else { return }
        
        // This query identifies the keychain item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
        
        // This dictionary contains the data to be saved.
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        // First, try to update an existing item.
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        // If the item doesn't exist, add a new one.
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }

    /// Reads a string securely from the Keychain.
    func read(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Deletes a specific item from the Keychain.
    func delete(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}


// MARK: - DATA MODELS

// A struct to make audio data exportable
struct AudioFile: FileDocument {
    static var readableContentTypes: [UTType] = [.wav]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}


// A simple struct for encoding the body of the POST requests
struct SearchRequestBody: Codable {
    let start_at: String
    let end_at: String
}

struct IdRequestBody: Codable {
    let id: Int
}

/// Represents a recording object from the initial search list.
struct Recording: Decodable, Identifiable, Equatable {
    let id: Int
    let created: String
    let duration: Int
    let sourceName: String?
    let destinationName: String?
    let hasRecording: Bool
    let callType: String

    // These are helper structs for decoding the nested source/destination objects
    private struct Source: Decodable {
        let name: String?
    }
    private struct Destination: Decodable {
        let name: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case created = "timestamp"
        case duration
        case source
        case destination
        case hasRecording = "has_recording?"
        case callType = "call_type"
    }
    
    // Custom initializer to handle the nested JSON structure from the API
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(Int.self, forKey: .id)
        created = try container.decode(String.self, forKey: .created)
        
        duration = (try container.decodeIfPresent(Int.self, forKey: .duration)) ?? 0
        hasRecording = (try container.decodeIfPresent(Bool.self, forKey: .hasRecording)) ?? false
        callType = (try container.decodeIfPresent(String.self, forKey: .callType)) ?? "unknown"

        let sourceObject = try container.decodeIfPresent(Source.self, forKey: .source)
        sourceName = sourceObject?.name
        
        let destinationObject = try container.decodeIfPresent(Destination.self, forKey: .destination)
        destinationName = destinationObject?.name
    }
    
    // Formatted properties for display in the UI
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = formatter.date(from: created) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .none
            displayFormatter.timeStyle = .medium
            return displayFormatter.string(from: date)
        }
        return "Invalid Date"
    }
    
    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Represents the API response from the search endpoint.
struct RecordingSearchResponse: Decodable {
    let data: [Recording]?
}

// Represents the successful JSON response when fetching audio data
struct AudioSuccessData: Decodable {
    let file: String 
}
struct AudioSuccessResponse: Decodable {
    let status: String
    let data: AudioSuccessData
}

// Represents a generic success/fail response, e.g., for deletion
struct GenericApiResponse: Decodable {
    let status: String
}


// MARK: - MAIN VIEW (INPUT FORM)
struct Dial9DownloaderView: View {
    
    // MARK: - STATE PROPERTIES
    @State private var authToken: String = ""
    @State private var apiSecret: String = ""
    @AppStorage("shouldSaveChanges") private var shouldSaveChanges: Bool = false
    @State private var showInfoAlert = false

    @State private var selectedDate = Date()
    @State private var recordings: [Recording] = []
    @State private var isLoading = false
    @State private var statusMessage: String = "Enter your details and fetch recordings."
    @State private var isNavigationActive = false
    
    // MARK: - BODY
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section {
                        SecureField("Enter Your X-Auth-Token", text: $authToken)
                        SecureField("Enter Your X-Auth-Secret", text: $apiSecret)
                        Toggle("Save Details", isOn: $shouldSaveChanges)
                    } header: {
                        HStack {
                            Text("API Credentials")
                            Button(action: { showInfoAlert = true }) {
                                Image(systemName: "info.circle")
                            }
                        }
                    }
                    
                    Section(header: Text("Search Date").font(.headline)) {
                        DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    }
                    
                    Button(action: fetchRecordings) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Fetching...").padding(.leading, 8)
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("Fetch Recordings")
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.white).padding().background(Color.blue).cornerRadius(10)
                    .disabled(isLoading || authToken.isEmpty || apiSecret.isEmpty)
                }
                
                Text(statusMessage).font(.footnote).foregroundColor(.secondary).padding()
                
                NavigationLink(destination: RecordingsListView(recordings: $recordings, authToken: authToken, apiSecret: apiSecret), isActive: $isNavigationActive) { EmptyView() }
            }
            .navigationTitle("Dial 9 Call History") // Updated app name
            .onAppear(perform: loadCredentials)
            .onChange(of: authToken, perform: credentialsChanged)
            .onChange(of: apiSecret, perform: credentialsChanged)
            .onChange(of: shouldSaveChanges, perform: savePreferenceChanged)
            .onChange(of: selectedDate) { _ in clearState() }
            .alert("API Credentials", isPresented: $showInfoAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can find your API keys in connect.dial9.co.uk")
            }
        }
    }
    
    // MARK: - HELPER & API FUNCTIONS
    private func loadCredentials() {
        if shouldSaveChanges {
            authToken = KeychainHelper.standard.read(for: "authToken") ?? ""
            apiSecret = KeychainHelper.standard.read(for: "apiSecret") ?? ""
        }
    }
    
    private func credentialsChanged(_: String) {
        if shouldSaveChanges {
            KeychainHelper.standard.save(authToken, for: "authToken")
            KeychainHelper.standard.save(apiSecret, for: "apiSecret")
        }
    }
    
    private func savePreferenceChanged(to newValue: Bool) {
        if newValue {
            KeychainHelper.standard.save(authToken, for: "authToken")
            KeychainHelper.standard.save(apiSecret, for: "apiSecret")
        } else {
            KeychainHelper.standard.delete(for: "authToken")
            KeychainHelper.standard.delete(for: "apiSecret")
        }
    }
    
    private func clearState() {
        recordings.removeAll()
        statusMessage = "Date changed. Press fetch to search again."
        isNavigationActive = false
    }
    
    /// Fetches the initial list of recordings from the API for a specific date.
    private func fetchRecordings() {
        isLoading = true
        statusMessage = "Fetching recordings list..."
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            self.statusMessage = "Error: Could not calculate date range."
            self.isLoading = false
            return
        }

        let apiDateFormatter = DateFormatter()
        apiDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        apiDateFormatter.timeZone = calendar.timeZone

        let fromDateString = apiDateFormatter.string(from: startOfDay)
        let toDateString = apiDateFormatter.string(from: endOfDay)
        
        let url = URL(string: "https://connectapi.dial9.co.uk/api/v2/logs/search")!
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken, forHTTPHeaderField: "X-Auth-Token")
        request.setValue(apiSecret, forHTTPHeaderField: "X-Auth-Secret")

        let requestBody = SearchRequestBody(start_at: fromDateString, end_at: toDateString)
        request.httpBody = try? JSONEncoder().encode(requestBody)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.statusMessage = "Network Error: \(error.localizedDescription)"
                    return
                }
                guard let data = data else {
                    self.statusMessage = "Error: No data received."
                    return
                }
                
                do {
                    let decodedResponse = try JSONDecoder().decode(RecordingSearchResponse.self, from: data)
                    let foundRecordings = decodedResponse.data ?? []
                    
                    if foundRecordings.isEmpty {
                        self.statusMessage = "No recordings found for this date."
                    } else {
                        self.recordings = foundRecordings.sorted(by: { $0.created > $1.created })
                        self.statusMessage = "Success! Found \(self.recordings.count) recording(s)."
                        self.isNavigationActive = true
                    }
                } catch {
                    self.statusMessage = "Error decoding list: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}


// MARK: - RECORDINGS LIST VIEW
struct RecordingsListView: View {
    @Binding var recordings: [Recording] // Use a Binding to allow deletion
    let authToken: String
    let apiSecret: String
    
    @State private var statusMessage: String = ""
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var currentlyPlayingID: Int?
    @State private var isFetchingForId: Int?
    
    @State private var playbackProgress: Double = 0
    @State private var isScrubbing = false
    
    @State private var fileToExport: AudioFile?
    @State private var showFileExporter = false
    
    @State private var recordingToDelete: Recording?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack {
            List(recordings) { recording in
                recordingRowView(recording)
            }
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.footnote).foregroundColor(.secondary).padding()
            }
        }
        .animation(.default, value: currentlyPlayingID)
        .navigationTitle("Recordings (\(recordings.count))")
        .onDisappear(perform: cleanup)
        .fileExporter(isPresented: $showFileExporter, document: fileToExport, contentType: .wav) { result in
            switch result {
            case .success(let url):
                statusMessage = "Saved to \(url.lastPathComponent)"
            case .failure(let error):
                statusMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
        .alert("Delete Recording?", isPresented: $showDeleteConfirmation, presenting: recordingToDelete) { recording in
            Button("Delete", role: .destructive) {
                performDelete(for: recording)
            }
            Button("Cancel", role: .cancel) { }
        } message: { recording in
            Text("Are you sure you want to permanently delete the recording for the call from \(recording.sourceName ?? "Unknown")?")
        }
    }
    
    @ViewBuilder
    private func recordingRowView(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: recording.callType == "incoming" ? "arrow.down.left" : "arrow.up.right")
                    .foregroundColor(recording.callType == "incoming" ? .green : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("From: \(recording.sourceName ?? "Unknown")").font(.headline)
                    Text("To: \(recording.destinationName ?? "Unknown")").font(.subheadline)
                    HStack {
                        Image(systemName: "clock"); Text(recording.formattedDate)
                        Spacer()
                        Image(systemName: "hourglass"); Text(recording.formattedDuration)
                    }
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                
                if isFetchingForId == recording.id {
                    ProgressView()
                } else if recording.hasRecording {
                    // Action buttons
                    Button(action: { playOrStopRecording(recording) }) {
                        Image(systemName: currentlyPlayingID == recording.id ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(currentlyPlayingID == recording.id ? .red : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { downloadRecording(recording) }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        recordingToDelete = recording
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Show the detailed playback controls only for the currently playing item
            if currentlyPlayingID == recording.id {
                playbackControls(for: recording)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func playbackControls(for recording: Recording) -> some View {
        VStack {
            Slider(value: $playbackProgress, in: 0...1) { editing in
                isScrubbing = editing
                if !editing {
                    seek(to: playbackProgress)
                }
            }

            HStack {
                Text(timeString(from: (player?.currentTime().seconds ?? 0) * (isScrubbing ? 0 : 1) + (isScrubbing ? playbackProgress * Double(recording.duration) : 0)))
                Spacer()
                Text(timeString(from: Double(recording.duration)))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Core Logic
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func seek(to progress: Double) {
        guard let player = player, let duration = player.currentItem?.duration else { return }
        let durationInSeconds = CMTimeGetSeconds(duration)
        if durationInSeconds.isFinite && durationInSeconds > 0 {
            let seekTime = durationInSeconds * progress
            player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600))
        }
    }
    
    private func timeString(from totalSeconds: Double) -> String {
        guard totalSeconds.isFinite else { return "00:00" }
        let seconds = Int(totalSeconds) % 60
        let minutes = Int(totalSeconds) / 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func playOrStopRecording(_ recording: Recording) {
        if currentlyPlayingID == recording.id {
            cleanup()
            currentlyPlayingID = nil
            statusMessage = "Playback stopped."
            return
        }
        cleanup()
        
        fetchRecordingData(for: recording) { result in
            switch result {
            case .success(let audioData):
                currentlyPlayingID = recording.id
                playAudio(from: audioData, for: recording)
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }
    
    private func downloadRecording(_ recording: Recording) {
        fetchRecordingData(for: recording) { result in
            switch result {
            case .success(let audioData):
                self.fileToExport = AudioFile(data: audioData)
                self.showFileExporter = true
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }
    
    private func performDelete(for recording: Recording) {
        statusMessage = "Deleting recording \(recording.id)..."

        let url = URL(string: "https://connectapi.dial9.co.uk/api/v2/logs/delete_recording")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken, forHTTPHeaderField: "X-Auth-Token")
        request.setValue(apiSecret, forHTTPHeaderField: "X-Auth-Secret")
        
        let requestBody = IdRequestBody(id: recording.id)
        request.httpBody = try? JSONEncoder().encode(requestBody)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    statusMessage = "Delete failed: \(error.localizedDescription)"
                    return
                }
                guard let data = data else {
                    statusMessage = "Delete failed: No response from server."
                    return
                }
                
                if let response = try? JSONDecoder().decode(GenericApiResponse.self, from: data), response.status == "success" {
                    statusMessage = "Recording \(recording.id) deleted."
                    recordings.removeAll { $0.id == recording.id }
                } else {
                    statusMessage = "Delete failed: Server returned an error."
                }
            }
        }.resume()
    }

    private func fetchRecordingData(for recording: Recording, completion: @escaping (Result<Data, Error>) -> Void) {
        isFetchingForId = recording.id
        statusMessage = "Fetching data for ID \(recording.id)..."

        let url = URL(string: "https://connectapi.dial9.co.uk/api/v2/logs/recording")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken, forHTTPHeaderField: "X-Auth-Token")
        request.setValue(apiSecret, forHTTPHeaderField: "X-Auth-Secret")
        
        let requestBody = IdRequestBody(id: recording.id)
        request.httpBody = try? JSONEncoder().encode(requestBody)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isFetchingForId = nil
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let responseData = data else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received."])))
                    return
                }

                do {
                    let successResponse = try JSONDecoder().decode(AudioSuccessResponse.self, from: responseData)
                    if successResponse.status == "success" {
                        let sanitizedBase64 = successResponse.data.file.filter { !" \n\t\r".contains($0) }
                        
                        guard let audioData = Data(base64Encoded: sanitizedBase64) else {
                            completion(.failure(NSError(domain: "", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio content was corrupt or missing."])))
                            return
                        }

                        let wavData = createWavFile(from: audioData)
                        completion(.success(wavData))
                        
                    } else {
                        completion(.failure(NSError(domain: "", code: -3, userInfo: [NSLocalizedDescriptionKey: "API status was not 'success'."])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func createWavFile(from rawData: Data) -> Data {
        var sampleRate: Int32 = 8000
        var channels: Int16 = 1
        var bitsPerSample: Int16 = 16
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        var chunkSize = Int32(36 + rawData.count)
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        var subchunk1Size: Int32 = 16
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: Int16 = 1
        header.append(Data(bytes: &audioFormat, count: 2))
        header.append(Data(bytes: &channels, count: 2))
        header.append(Data(bytes: &sampleRate, count: 4))
        var byteRate = sampleRate * Int32(channels * bitsPerSample / 8)
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = channels * bitsPerSample / 8
        header.append(Data(bytes: &blockAlign, count: 2))
        header.append(Data(bytes: &bitsPerSample, count: 2))
        header.append("data".data(using: .ascii)!)
        var subchunk2Size = Int32(rawData.count)
        header.append(Data(bytes: &subchunk2Size, count: 4))
        return header + rawData
    }
    
    private func playAudio(from audioData: Data, for recording: Recording) {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let localFileUrl = tempDir.appendingPathComponent("recording-\(recording.id).wav")
            try audioData.write(to: localFileUrl)
            
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            let playerItem = AVPlayerItem(url: localFileUrl)
            self.player = AVPlayer(playerItem: playerItem)
            
            // Add time observer for the progress bar
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            self.timeObserver = self.player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
                guard let duration = self.player?.currentItem?.duration else { return }
                let durationSeconds = CMTimeGetSeconds(duration)
                let currentTimeSeconds = CMTimeGetSeconds(time)
                
                if durationSeconds > 0 && !self.isScrubbing {
                    self.playbackProgress = currentTimeSeconds / durationSeconds
                }
            }
            
            self.player?.play()
            
            statusMessage = "Playing recording from: \(recording.sourceName ?? "Unknown")"
        } catch {
            statusMessage = "Failed to play audio: \(error.localizedDescription)"
        }
    }
}


// MARK: - PREVIEW PROVIDER
struct Dial9DownloaderView_Previews: PreviewProvider {
    static var previews: some View {
        Dial9DownloaderView()
    }
}

