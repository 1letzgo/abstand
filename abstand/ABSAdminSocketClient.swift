import Foundation

/// Minimaler Socket.IO-/Engine.IO-v4-Client (WebSocket) für Admin-Events wie `task_progress`.
/// Kein vollständiger Socket.IO-Stack — nur Auth + Event-Empfang für M4B-Encode.
@MainActor
final class ABSAdminSocketClient {
  enum Event {
    case taskProgress(libraryItemId: String, percent: Double)
    case taskFinished(libraryItemId: String, action: String, failed: Bool)
    case connected
    case disconnected
  }

  private let urlSession: URLSession
  private var webSocket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var pingIntervalNs: UInt64 = 25_000_000_000
  private var token: String = ""
  private var baseURL: URL?
  private var wantsConnection = false
  /// Aufeinanderfolgende Reconnects ohne erfolgreiche Verbindung — steuert den Backoff.
  private var reconnectAttempt = 0

  var onEvent: ((Event) -> Void)?
  /// Liefert beim (Re-)Connect das aktuelle Token — ein im ersten `connect` gemerktes JWT kann
  /// nach Stunden (langer Encode) längst rotiert sein; dann würde `auth` stumm abgelehnt.
  var tokenProvider: (() -> String)?

  /// Eigene Session mit Trust-Delegate (selbstsignierte Zertifikate lokaler Server wie im API-Client).
  init(
    urlSession: URLSession = URLSession(
      configuration: .default, delegate: AbstandTrustDelegate.shared, delegateQueue: nil)
  ) {
    self.urlSession = urlSession
  }

  func connect(serverURL: URL, token: String) {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    // Schon mit demselben Server verbunden (z. B. zweiter Encode-Job): nicht neu aufbauen — das
    // Abreißen der laufenden Verbindung hat früher eine Reconnect-Kaskade ausgelöst.
    if wantsConnection, webSocket != nil, baseURL == serverURL { return }
    wantsConnection = true
    self.token = trimmed
    self.baseURL = serverURL
    disconnectSocketOnly()
    guard let wsURL = Self.socketIOWebSocketURL(from: serverURL) else { return }
    var request = URLRequest(url: wsURL)
    request.timeoutInterval = 30
    AbstandCustomHeadersStore.apply(to: &request)
    let task = urlSession.webSocketTask(with: request)
    webSocket = task
    task.resume()
    receiveTask = Task { [weak self] in
      await self?.receiveLoop()
    }
  }

  func disconnect() {
    wantsConnection = false
    reconnectAttempt = 0
    disconnectSocketOnly()
    onEvent?(.disconnected)
  }

  private func disconnectSocketOnly() {
    receiveTask?.cancel()
    receiveTask = nil
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
  }

  private func receiveLoop() async {
    // Eigene Socket-Instanz merken: ein neuer `connect` ersetzt `self.webSocket` — dann darf diese
    // (alte) Schleife nicht mehr reconnecten, sonst reißt sie die neue Verbindung wieder ab.
    guard let ownSocket = webSocket else { return }
    while !Task.isCancelled {
      guard let webSocket, webSocket === ownSocket else { return }
      do {
        let message = try await webSocket.receive()
        switch message {
        case .string(let text):
          await handlePacket(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            await handlePacket(text)
          }
        @unknown default:
          break
        }
      } catch {
        // Abgebrochen oder durch neue Verbindung ersetzt: nichts tun.
        guard !Task.isCancelled, self.webSocket === ownSocket else { return }
        if wantsConnection, let baseURL {
          // Backoff 2, 4, 8 … max. 60 s — statt dauerhaft alle 2 s gegen einen toten Server.
          let delay = min(60, 2 << min(reconnectAttempt, 5))
          reconnectAttempt += 1
          do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) } catch { return }
          guard wantsConnection, self.webSocket === ownSocket else { return }
          let fresh = tokenProvider?().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          webSocket.cancel(with: .goingAway, reason: nil)
          self.webSocket = nil
          connect(serverURL: baseURL, token: fresh.isEmpty ? token : fresh)
        } else {
          onEvent?(.disconnected)
        }
        return
      }
    }
  }

  private func handlePacket(_ raw: String) async {
    guard !raw.isEmpty else { return }
    // Engine.IO: optional binary prefix; Payload beginnt mit Ziffer.
    let packet = raw
    guard let typeChar = packet.first, let type = Int(String(typeChar)) else { return }
    let body = String(packet.dropFirst())

    switch type {
    case 0:
      // open — pingInterval aus JSON
      if let data = body.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let intervalMs = json["pingInterval"] as? Double
      {
        pingIntervalNs = UInt64(max(5_000, intervalMs) * 1_000_000)
      }
      // Socket.IO Namespace connect
      sendRaw("40")
    case 2:
      // Engine.IO ping → pong
      sendRaw("3")
    case 4:
      // Socket.IO message: 0=connect, 2=event, …
      guard let sioType = body.first, let sio = Int(String(sioType)) else { return }
      let payload = String(body.dropFirst())
      switch sio {
      case 0:
        // Namespace verbunden → Auth
        reconnectAttempt = 0
        sendEvent("auth", arguments: [token])
        onEvent?(.connected)
      case 2:
        parseEventPayload(payload)
      default:
        break
      }
    default:
      break
    }
  }

  private func parseEventPayload(_ payload: String) {
    guard let data = payload.data(using: .utf8),
      let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
      let name = arr.first as? String
    else { return }

    switch name {
    case "task_progress":
      guard arr.count >= 2, let obj = arr[1] as? [String: Any] else { return }
      let lid = (obj["libraryItemId"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !lid.isEmpty else { return }
      let percent: Double
      if let d = obj["progress"] as? Double {
        percent = d
      } else if let i = obj["progress"] as? Int {
        percent = Double(i)
      } else if let s = obj["progress"] as? String, let d = Double(s) {
        percent = d
      } else {
        return
      }
      onEvent?(.taskProgress(libraryItemId: lid, percent: min(100, max(0, percent))))

    case "task_finished", "task_started":
      guard arr.count >= 2, let obj = arr[1] as? [String: Any] else { return }
      let action = (obj["action"] as? String) ?? ""
      let dataObj = obj["data"] as? [String: Any]
      let lid = (dataObj?["libraryItemId"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !lid.isEmpty else { return }
      if name == "task_finished" {
        let failed = (obj["isFailed"] as? Bool) ?? false
        onEvent?(.taskFinished(libraryItemId: lid, action: action, failed: failed))
      }

    default:
      break
    }
  }

  private func sendEvent(_ name: String, arguments: [Any]) {
    var parts: [Any] = [name]
    parts.append(contentsOf: arguments)
    guard JSONSerialization.isValidJSONObject(parts),
      let data = try? JSONSerialization.data(withJSONObject: parts),
      let json = String(data: data, encoding: .utf8)
    else { return }
    sendRaw("42" + json)
  }

  private func sendRaw(_ text: String) {
    webSocket?.send(.string(text)) { _ in }
  }

  static func socketIOWebSocketURL(from serverURL: URL) -> URL? {
    var c = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
    let scheme = (serverURL.scheme ?? "http").lowercased()
    c?.scheme = (scheme == "https" || scheme == "wss") ? "wss" : "ws"
    var path = serverURL.path
    if path.hasSuffix("/") { path.removeLast() }
    c?.path = path.isEmpty ? "/socket.io/" : "\(path)/socket.io/"
    c?.queryItems = [
      URLQueryItem(name: "EIO", value: "4"),
      URLQueryItem(name: "transport", value: "websocket"),
    ]
    return c?.url
  }
}
