import Foundation
import Security

/// Ошибка с понятным текстом от сервера CRM.
struct APIError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

/// Ключ входа хранится в связке ключей iPhone (Keychain), а не в обычных настройках.
enum Keychain {
    private static let service = "ru.neophoenix.team"
    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

/// Работа с сервером CRM (neophoenix.ru/api). Все запросы — с ключом в заголовке X-App-Token.
final class API {
    static let shared = API()
    static let defaultServer = "https://neophoenix.ru"

    var server: String {
        get { UserDefaults.standard.string(forKey: "server") ?? API.defaultServer }
        set { UserDefaults.standard.set(newValue, forKey: "server") }
    }
    var token: String? {
        get { Keychain.get("token") }
        set { Keychain.set(newValue, for: "token") }
    }
    /// Сервер ответил «Требуется вход» — ключ отозван или истёк.
    var onUnauthorized: (@MainActor () -> Void)?

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()
    private let decoder = JSONDecoder()

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "GET", body: nil)
    }
    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "POST", body: body)
    }

    private func send<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        guard let url = URL(string: server + path) else { throw APIError(message: "Неверный адрес сервера", status: 0) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue(token, forHTTPHeaderField: "X-App-Token") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw APIError(message: "Нет связи с сервером. Проверьте интернет.", status: 0) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let err = try? decoder.decode(ErrorBody.self, from: data), err.ok == false {
            if status == 401 { await MainActor.run { self.onUnauthorized?() } }
            throw APIError(message: err.error ?? "Ошибка сервера", status: status)
        }
        guard (200..<300).contains(status) else {
            if status == 401 { await MainActor.run { self.onUnauthorized?() } }
            throw APIError(message: "Ошибка сервера (\(status))", status: status)
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError(message: "Сервер ответил непонятно. Обновите приложение.", status: status) }
    }

    /// Отправка файла (фото, документ) — multipart/form-data, как форма в браузере.
    func upload<T: Decodable>(_ path: String, fields: [String: String], fileField: String, fileName: String, mime: String, data fileData: Data, as type: T.Type = T.self) async throws -> T {
        guard let url = URL(string: server + path) else { throw APIError(message: "Неверный адрес сервера", status: 0) }
        let boundary = "np-" + UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue(token, forHTTPHeaderField: "X-App-Token") }
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }
        for (k, v) in fields {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        let safeName = fileName.replacingOccurrences(of: "\"", with: "")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        add("\r\n--\(boundary)--\r\n")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.upload(for: req, from: body) }
        catch { throw APIError(message: "Не удалось отправить файл. Проверьте интернет.", status: 0) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let err = try? decoder.decode(ErrorBody.self, from: data), err.ok == false { throw APIError(message: err.error ?? "Ошибка сервера", status: status) }
        guard (200..<300).contains(status) else { throw APIError(message: "Ошибка сервера (\(status))", status: status) }
        return try decoder.decode(T.self, from: data)
    }

    /// Скачать файл, доступный только сотрудникам (вложения чата).
    func download(_ path: String) async throws -> (Data, String?) {
        guard let url = URL(string: server + path) else { throw APIError(message: "Неверный адрес", status: 0) }
        var req = URLRequest(url: url)
        if let token { req.setValue(token, forHTTPHeaderField: "X-App-Token") }
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        guard let http, (200..<300).contains(http.statusCode) else { throw APIError(message: "Файл недоступен", status: http?.statusCode ?? 0) }
        return (data, http.value(forHTTPHeaderField: "Content-Type"))
    }

    private struct ErrorBody: Decodable { let ok: Bool?; let error: String? }
}
