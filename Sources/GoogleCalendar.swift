import AppKit
import CryptoKit
import Network
import Security

final class GoogleCalendar {
    enum Availability {
        case disconnected
        case checking
        case free
        case busy
        case unavailable(String)

        var title: String {
            switch self {
            case .disconnected: return "Google Calendar: not connected"
            case .checking: return "Google Calendar: checking…"
            case .free: return "Google Calendar: available"
            case .busy: return "Google Calendar: meeting in progress"
            case .unavailable: return "Google Calendar: unable to check"
            }
        }

        var allowsReminders: Bool {
            switch self {
            case .disconnected, .free: return true
            case .checking, .busy, .unavailable: return false
            }
        }
    }

    var onAvailabilityChange: ((Availability) -> Void)?
    var onSignInResult: ((Result<Void, Error>) -> Void)?
    private(set) var availability: Availability = .disconnected {
        didSet { onAvailabilityChange?(availability) }
    }
    var isConnected: Bool { refreshToken != nil }
    var savedClientID: String { UserDefaults.standard.string(forKey: "googleClientID") ?? "" }
    var sharedClientID: String? {
        guard let url = Bundle.main.url(forResource: "GoogleOAuthClientID", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let clientID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clientID.isEmpty ? nil : clientID
    }

    private let keychainService = "com.rachel.ice-bear-reminder.google-calendar"
    private let session = URLSession(configuration: .ephemeral)
    private var refreshToken: String?
    private var accessToken: String?
    private var accessTokenExpires = Date.distantPast
    private var listener: NWListener?
    private var signInTimeout: DispatchWorkItem?
    private var busyStartTimer: Timer?
    private var isAuthorizing = false
    private var authorization: (clientID: String, verifier: String, state: String, redirectURI: String)?
    private var pendingChecks: [(Result<Bool, Error>) -> Void] = []
    private var generation = 0

    init() {
        do {
            refreshToken = try readRefreshToken()
            availability = refreshToken == nil ? .disconnected : .checking
        } catch {
            availability = .unavailable(error.localizedDescription)
        }
    }

    func connect(clientID: String) throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.contains(where: \.isWhitespace) else {
            throw CalendarError("Paste a Google OAuth Desktop app client ID.")
        }
        cancelAuthorization()
        isAuthorizing = false
        generation += 1
        pendingChecks.removeAll()
        isChecking = false
        busyStartTimer?.invalidate()
        let attempt = generation
        let verifier = randomURLSafeString()
        let state = randomURLSafeString()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        isAuthorizing = true
        self.listener = listener
        authorization = nil
        availability = .checking
        listener.stateUpdateHandler = { [weak self, weak listener] listenerState in
            guard let self, let listener, self.generation == attempt else { return }
            switch listenerState {
            case .ready:
                guard let port = listener.port?.rawValue else {
                    self.finishSignIn(.failure(CalendarError("Could not open the local sign-in callback.")))
                    return
                }
                let redirectURI = "http://127.0.0.1:\(port)"
                self.authorization = (clientID, verifier, state, redirectURI)
                var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).urlSafeBase64
                url.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.freebusy"),
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                    URLQueryItem(name: "code_challenge", value: challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "state", value: state),
                ]
                guard let signInURL = url.url, NSWorkspace.shared.open(signInURL) else {
                    self.finishSignIn(.failure(CalendarError("Could not open your browser for Google sign-in.")))
                    return
                }
            case .failed(let error):
                self.finishSignIn(.failure(error))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.generation == attempt else { return }
            connection.start(queue: .main)
            self.receiveCallback(connection, request: Data(), attempt: attempt)
        }
        listener.start(queue: .main)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == attempt else { return }
            self.finishSignIn(.failure(CalendarError("Google sign-in timed out. Try connecting again.")))
        }
        signInTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timeout)
    }

    func disconnect() throws {
        generation += 1
        cancelAuthorization()
        isAuthorizing = false
        busyStartTimer?.invalidate()
        try deleteRefreshToken()
        refreshToken = nil
        accessToken = nil
        accessTokenExpires = .distantPast
        pendingChecks.removeAll()
        isChecking = false
        availability = .disconnected
    }

    func checkAvailability(completion: ((Result<Bool, Error>) -> Void)? = nil) {
        guard !isAuthorizing else { return }
        guard let refreshToken else {
            availability = .disconnected
            completion?(.success(false))
            return
        }
        if let completion { pendingChecks.append(completion) }
        guard !isChecking else { return }
        isChecking = true
        switch availability {
        case .free, .busy: break
        default: availability = .checking
        }
        let attempt = generation
        withAccessToken(refreshToken: refreshToken) { [weak self] result in
            guard let self, self.generation == attempt else { return }
            switch result {
            case .failure(let error): self.finishCheck(.failure(error))
            case .success(let token): self.fetchBusy(token: token, attempt: attempt)
            }
        }
    }

    private var isChecking = false

    private func receiveCallback(_ connection: NWConnection, request: Data, attempt: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, self.generation == attempt else { connection.cancel(); return }
            var request = request
            if let data { request.append(data) }
            guard request.count <= 8192, error == nil else { connection.cancel(); return }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if isComplete { connection.cancel() }
                else { self.receiveCallback(connection, request: request, attempt: attempt) }
                return
            }
            guard let firstLine = text.components(separatedBy: "\r\n").first,
                  firstLine.hasPrefix("GET /"),
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://127.0.0.1\(target)"),
                  components.path == "/",
                  let authorization = self.authorization else {
                self.reply(connection, status: "400 Bad Request", body: "Invalid sign-in callback.")
                return
            }
            let values = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            guard values["state"] == authorization.state else {
                self.reply(connection, status: "400 Bad Request", body: "Invalid sign-in state.")
                return
            }
            if let oauthError = values["error"] {
                self.reply(connection, status: "200 OK", body: "Google sign-in was cancelled. You can close this tab.")
                self.finishSignIn(.failure(CalendarError("Google sign-in: \(oauthError)")))
                return
            }
            guard let code = values["code"], !code.isEmpty else {
                self.reply(connection, status: "400 Bad Request", body: "Missing sign-in code.")
                return
            }
            self.reply(connection, status: "200 OK", body: "Ice Bear is connected to Google Calendar. You can close this tab.")
            self.cancelAuthorization()
            self.exchangeCode(code, authorization: authorization, attempt: attempt)
        }
    }

    private func reply(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=\"utf-8\"><title>Ice Bear Look Away</title><p>\(body)</p>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func exchangeCode(_ code: String, authorization: (clientID: String, verifier: String, state: String, redirectURI: String), attempt: Int) {
        tokenRequest([
            "client_id": authorization.clientID,
            "code": code,
            "code_verifier": authorization.verifier,
            "redirect_uri": authorization.redirectURI,
            "grant_type": "authorization_code",
        ]) { [weak self] result in
            guard let self, self.generation == attempt else { return }
            switch result {
            case .failure(let error): self.finishSignIn(.failure(error))
            case .success(let response):
                guard let refreshToken = response["refresh_token"] as? String else {
                    self.finishSignIn(.failure(CalendarError("Google did not provide a refresh token. Try connecting again.")))
                    return
                }
                do {
                    try self.saveRefreshToken(refreshToken)
                    UserDefaults.standard.set(authorization.clientID, forKey: "googleClientID")
                    self.refreshToken = refreshToken
                    self.updateAccessToken(response)
                    self.finishSignIn(.success(()))
                    self.checkAvailability()
                } catch {
                    self.finishSignIn(.failure(error))
                }
            }
        }
    }

    private func withAccessToken(refreshToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        if let accessToken, accessTokenExpires > Date().addingTimeInterval(60) {
            completion(.success(accessToken))
            return
        }
        tokenRequest([
            "client_id": savedClientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let response):
                self.updateAccessToken(response)
                if let accessToken = self.accessToken { completion(.success(accessToken)) }
                else { completion(.failure(CalendarError("Google did not provide an access token."))) }
            }
        }
    }

    private func updateAccessToken(_ response: [String: Any]) {
        accessToken = response["access_token"] as? String
        accessTokenExpires = Date().addingTimeInterval((response["expires_in"] as? Double) ?? 3600)
    }

    private func fetchBusy(token: String, attempt: Int) {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/freeBusy")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let now = Date()
        let formatter = ISO8601DateFormatter()
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "timeMin": formatter.string(from: now.addingTimeInterval(-1)),
                "timeMax": formatter.string(from: now.addingTimeInterval(120)),
                "items": [["id": "primary"]],
            ])
        } catch {
            finishCheck(.failure(error))
            return
        }
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == attempt else { return }
                if let error { self.finishCheck(.failure(error)); return }
                guard let data, let response = response as? HTTPURLResponse else {
                    self.finishCheck(.failure(CalendarError("Google Calendar returned no response.")))
                    return
                }
                guard response.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let calendars = json["calendars"] as? [String: Any],
                      let primary = calendars["primary"] as? [String: Any],
                      let busy = primary["busy"] as? [[String: String]] else {
                    self.finishCheck(.failure(CalendarError("Google Calendar could not check availability (HTTP \(response.statusCode)).")))
                    return
                }
                if let errors = primary["errors"] as? [Any], !errors.isEmpty {
                    self.finishCheck(.failure(CalendarError("Google Calendar could not read the primary calendar.")))
                    return
                }
                var busyNow = false
                var nextStart: Date?
                for interval in busy {
                    guard let start = interval["start"].flatMap(parseCalendarDate),
                          let end = interval["end"].flatMap(parseCalendarDate), end > start else {
                        self.finishCheck(.failure(CalendarError("Google Calendar returned an invalid meeting time.")))
                        return
                    }
                    if start <= Date().addingTimeInterval(20) && end > Date() { busyNow = true }
                    if start > Date().addingTimeInterval(20) {
                        if let previous = nextStart {
                            nextStart = min(previous, start)
                        } else {
                            nextStart = start
                        }
                    }
                }
                self.busyStartTimer?.invalidate()
                if let nextStart {
                    self.busyStartTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, nextStart.timeIntervalSinceNow - 20), repeats: false) { [weak self] _ in
                        self?.availability = .busy
                    }
                }
                self.finishCheck(.success(busyNow))
            }
        }.resume()
    }

    private func tokenRequest(_ fields: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.sorted().joined(separator: "&").data(using: .utf8)
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(error)); return }
                guard let data, let response = response as? HTTPURLResponse,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(CalendarError("Google sign-in returned an invalid response.")))
                    return
                }
                guard (200..<300).contains(response.statusCode) else {
                    let message = json["error_description"] as? String ?? json["error"] as? String ?? "HTTP \(response.statusCode)"
                    completion(.failure(CalendarError("Google sign-in: \(message)")))
                    return
                }
                completion(.success(json))
            }
        }.resume()
    }

    private func finishCheck(_ result: Result<Bool, Error>) {
        isChecking = false
        switch result {
        case .success(let busy): availability = busy ? .busy : .free
        case .failure(let error):
            busyStartTimer?.invalidate()
            availability = .unavailable(error.localizedDescription)
        }
        let callbacks = pendingChecks
        pendingChecks.removeAll()
        callbacks.forEach { $0(result) }
    }

    private func finishSignIn(_ result: Result<Void, Error>) {
        cancelAuthorization()
        isAuthorizing = false
        if case .failure(let error) = result {
            availability = isConnected ? .unavailable(error.localizedDescription) : .disconnected
        }
        onSignInResult?(result)
        if case .failure = result, isConnected { checkAvailability() }
    }

    private func cancelAuthorization() {
        signInTimeout?.cancel()
        signInTimeout = nil
        listener?.cancel()
        listener = nil
        authorization = nil
    }

    private func readRefreshToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "primary",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw CalendarError("Could not read Google Calendar credentials from Keychain (\(status)).")
        }
        return token
    }

    private func saveRefreshToken(_ token: String) throws {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "primary",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: "primary",
            ]
            let update: [String: Any] = [kSecValueData as String: Data(token.utf8)]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw CalendarError("Could not save Google Calendar credentials in Keychain (\(status)).")
        }
    }

    private func deleteRefreshToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "primary",
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CalendarError("Could not remove Google Calendar credentials from Keychain (\(status)).")
        }
    }
}

private struct CalendarError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func randomURLSafeString() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = bytes.withUnsafeMutableBytes { buffer in
        SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    precondition(status == errSecSuccess, "Secure random number generation failed")
    return Data(bytes).urlSafeBase64
}

private func formEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func parseCalendarDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value)
}

private extension Data {
    var urlSafeBase64: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
