import Foundation

enum Redaction {
    static func token(_ value: String) -> String {
        guard value.count > 8 else { return "<redacted>" }
        return "\(value.prefix(4))…\(value.suffix(4))"
    }

    static func sanitizedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }
        components.queryItems = components.queryItems?.map { item in
            if ["code", "state", "code_verifier", "access_token", "refresh_token"].contains(item.name) {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.string ?? "<invalid-url>"
    }
}
