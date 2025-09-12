import Foundation

public enum ProSourceManager {
    /// Fetch multiple URLs concurrently and print their JSON contents.
    /// - Parameter urls: array of `URL` to fetch.
    public static func fetchAndPrintJSON(from urls: [URL]) async {
        if urls.isEmpty {
            print("No URLs provided.")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    await fetchAndPrintSingle(url: url)
                }
            }
        }
    }

    /// Convenience overload that accepts String URLs.
    /// Invalid URLs will be skipped (with a warning).
    public static func fetchAndPrintJSON(from urlStrings: [String]) async {
        let mapped = urlStrings.compactMap { URL(string: $0) }
        if mapped.count != urlStrings.count {
            print("Some strings were invalid URLs and were skipped.")
        }
        await fetchAndPrintJSON(from: mapped)
    }

    // MARK: - Private helpers

    private static func fetchAndPrintSingle(url: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check HTTP status code (if HTTP)
            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else {
                    print("HTTP \(http.statusCode) from \(url.absoluteString)")
                    if let s = String(data: data, encoding: .utf8) {
                        print("Response body (truncated):\n\(s.prefix(1000))")
                    }
                    return
                }
            }

            // Try to parse JSON
            let jsonObj = try JSONSerialization.jsonObject(with: data, options: [])

            // Pretty-print JSON
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted])
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                print("\n--- JSON from: \(url.absoluteString) ---\n")
                print(prettyString)
                print("\n--- end of \(url.host ?? url.absoluteString) ---\n")
            } else {
                print("Received JSON from \(url.absoluteString) but couldn't convert to string.")
            }
        } catch {
            print("Error fetching \(url.absoluteString): \(error.localizedDescription)")
        }
    }
}
