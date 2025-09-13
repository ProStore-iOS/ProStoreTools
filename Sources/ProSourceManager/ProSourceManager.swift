// ProSourceManager.swift
// ProSourceManager
//
// A small utility Swift Package module for fetching AltStore-style source JSON feeds.
// This file provides functions to fetch multiple URLs concurrently and either print
// their pretty-printed JSON to the console or return the pretty JSON as strings.
//
// NOTE: This file intentionally only handles fetching + printing / returning JSON.
// It does NOT merge sources — per the user's request.

import Foundation

public enum ProSourceManager {
    // MARK: - Public printing API

    /// Fetch multiple URLs concurrently and print their JSON contents to the console.
    /// - Parameter urls: array of `URL` to fetch.
    public static func fetchAndPrintJSON(from urls: [URL]) async {
        guard !urls.isEmpty else {
            print("⚠️ ProSourceManager: No URLs provided.")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask(priority: .background) {
                    await fetchAndPrintSingle(url: url)
                }
            }
        }
    }

    /// Convenience overload: accepts array of URL strings. Invalid strings are skipped with a warning.
    /// - Parameter urlStrings: array of URL strings to fetch.
    public static func fetchAndPrintJSON(from urlStrings: [String]) async {
        let mapped: [URL] = urlStrings.compactMap { URL(string: $0) }
        if mapped.count != urlStrings.count {
            print("⚠️ ProSourceManager: Some provided strings were not valid URLs and were skipped.")
        }
        await fetchAndPrintJSON(from: mapped)
    }

    // MARK: - Public returning API (for UI)

    /// Fetch multiple URLs concurrently and return an array of (URL, Result<String, Error>).
    /// The .success case contains a pretty-printed JSON string.
    /// Results preserve the input order.
    /// - Parameter urls: array of `URL` to fetch.
    public static func fetchJSONStrings(from urls: [URL]) async -> [(URL, Result<String, Error>)] {
        guard !urls.isEmpty else { return [] }

        // We'll collect (index, url, result) and then sort by index to preserve input order.
        var interimResults: [(Int, URL, Result<String, Error>)] = []

        await withTaskGroup(of: (Int, URL, Result<String, Error>).self) { group in
            for (idx, url) in urls.enumerated() {
                group.addTask(priority: .background) {
                    let res = await fetchSingleReturningString(url: url)
                    return (idx, url, res)
                }
            }

            for await entry in group {
                interimResults.append(entry)
            }
        }

        interimResults.sort { $0.0 < $1.0 }
        return interimResults.map { ($0.1, $0.2) }
    }

    /// Convenience overload: accepts array of URL strings and returns ordered results.
    /// - Parameter urlStrings: array of URL strings to fetch.
    public static func fetchJSONStrings(from urlStrings: [String]) async -> [(URL, Result<String, Error>)] {
        let mapped: [URL] = urlStrings.compactMap { URL(string: $0) }
        if mapped.count != urlStrings.count {
            // Not fatal — just warn
            print("⚠️ ProSourceManager: Some provided strings were not valid URLs and were skipped.")
        }
        return await fetchJSONStrings(from: mapped)
    }

    // MARK: - Private helpers

    /// Fetch a single URL and print its pretty-printed JSON or an error message.
    /// - Parameter url: URL to fetch.
    private static func fetchAndPrintSingle(url: URL) async {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0  // 10 seconds timeout

            let (data, response) = try await URLSession.shared.data(for: request)

            // If HTTP response, validate status code
            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else {
                    print("❌ ProSourceManager: HTTP \(http.statusCode) from \(url.absoluteString)")
                    if let body = String(data: data, encoding: .utf8) {
                        let truncated = String(body.prefix(1000))
                        print("Response body (truncated):\n\(truncated)")
                    }
                    return
                }
            }

            // Try to parse JSON
            do {
                let jsonObj = try JSONSerialization.jsonObject(with: data, options: [])
                let prettyData = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted])
                if let prettyString = String(data: prettyData, encoding: .utf8) {
                    print("\n--- JSON from: \(url.absoluteString) ---\n")
                    print(prettyString)
                    print("\n--- end of \(url.host ?? url.absoluteString) ---\n")
                } else {
                    // Fallback: raw string
                    if let raw = String(data: data, encoding: .utf8) {
                        print("✅ Received data from \(url.absoluteString) but couldn't pretty-print JSON (encoding issue). Raw:\n\(raw)")
                    } else {
                        print("✅ Received data from \(url.absoluteString) but couldn't decode it to text.")
                    }
                }
            } catch {
                // Not valid JSON, attempt to print raw body for debugging
                if let raw = String(data: data, encoding: .utf8) {
                    print("⚠️ ProSourceManager: Response from \(url.absoluteString) is not valid JSON. Raw body:\n\(raw)")
                } else {
                    print("⚠️ ProSourceManager: Response from \(url.absoluteString) is not valid JSON and could not be decoded.")
                }
            }
        } catch {
            print("❌ ProSourceManager: Error fetching \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    /// Fetch a single URL and return a pretty-printed JSON string or an Error.
    /// - Parameter url: URL to fetch.
    /// - Returns: `.success(prettyJSONString)` or `.failure(Error)`
    private static func fetchSingleReturningString(url: URL) async -> Result<String, Error> {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0  // 10 seconds timeout

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else {
                    let msg = "HTTP \(http.statusCode) from \(url.absoluteString)"
                    return .failure(NSError(domain: "ProSourceManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg]))
                }
            }

            // Parse and pretty-print JSON
            let jsonObj = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted])
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                return .success(prettyString)
            } else {
                // Fallback to raw string if encoding fails
                if let raw = String(data: data, encoding: .utf8) {
                    return .success(raw)
                } else {
                    return .failure(NSError(domain: "ProSourceManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode response from \(url.absoluteString) to string."] ))
                }
            }
        } catch {
            return .failure(error)
        }
    }
}
