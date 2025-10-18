import Foundation
import ZIPFoundation
import ZsignSwift
 
public enum ProStoreTools {
    public static func sign(
        ipaURL: URL,
        p12URL: URL,
        provURL: URL,
        p12Password: String,
        progressUpdate: @escaping (String) -> Void = { _ in },
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        SigningManager.sign(
            ipaURL: ipaURL,
            p12URL: p12URL,
            provURL: provURL,
            p12Password: p12Password,
            progressUpdate: progressUpdate,
            completion: completion
        )
    }
    
    public static func getExpirationDate(provURL: URL) -> Date? {
        guard let data = try? Data(contentsOf: provURL) else { return nil }
        return getExpirationDate(provData: data)
    }
    
    public static func getExpirationDate(provData: Data) -> Date? {
        let startTag = Data("<plist".utf8)
        let endTag = Data("</plist>".utf8)
        
        guard let startRange = provData.range(of: startTag),
              let endRange = provData.range(of: endTag) else {
            return nil
        }
        
        let plistDataSlice = provData[startRange.lowerBound..<endRange.upperBound]
        let plistData = Data(plistDataSlice)
        
        guard let parsed = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = parsed as? [String: Any],
              let expDate = dict["ExpirationDate"] as? Date else {
            return nil
        }
        
        return expDate
    }
}
 
fileprivate class SigningManager {
    static func sign(
        ipaURL: URL,
        p12URL: URL,
        provURL: URL,
        p12Password: String,
        progressUpdate: @escaping (String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                progressUpdate("Preparing files 📂")
                let (tmpRoot, inputsDir, workDir) = try prepareTemporaryWorkspace()
                defer {
                    cleanupTemporaryFiles(at: tmpRoot)
                }
                let (localIPA, localP12, localProv) = try copyInputFiles(
                    ipaURL: ipaURL,
                    p12URL: p12URL,
                    provURL: provURL,
                    to: inputsDir
                )
                progressUpdate("Unzipping IPA 🔓")
                try extractIPA(ipaURL: localIPA, to: workDir, progressUpdate: progressUpdate)
                let payloadDir = workDir.appendingPathComponent("Payload")
                let appDir = try findAppBundle(in: payloadDir)
                progressUpdate("Signing \(appDir.lastPathComponent) ✍️")
                let sema = DispatchSemaphore(value: 0)
                var signingError: Error?
                // Use the ZsignSwift API
                _ = Zsign.sign(
                    appPath: appDir.path,
                    provisionPath: localProv.path,
                    p12Path: localP12.path,
                    p12Password: p12Password,
                    entitlementsPath: "",
                    removeProvision: false
                ) { _, error in
                    signingError = error
                    sema.signal()
                }
                sema.wait()
                if let error = signingError {
                    throw error
                }
                progressUpdate("Zipping signed IPA 📦")
                let signedIPAURL = try createSignedIPA(
                    from: workDir,
                    originalIPAURL: ipaURL,
                    outputDir: tmpRoot,
                    progressUpdate: progressUpdate
                )
                completion(.success(signedIPAURL))
            } catch {
                completion(.failure(error))
            }
        }
    }
   
    // MARK: - workspace helpers
    static func prepareTemporaryWorkspace() throws -> (URL, URL, URL) {
        let fm = FileManager.default
        let tmpRoot = fm.temporaryDirectory.appendingPathComponent("zsign_ios_\(UUID().uuidString)")
        let inputs = tmpRoot.appendingPathComponent("inputs")
        let work = tmpRoot.appendingPathComponent("work")
        try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        return (tmpRoot, inputs, work)
    }
   
    static func copyInputFiles(
        ipaURL: URL,
        p12URL: URL,
        provURL: URL,
        to inputsDir: URL
    ) throws -> (URL, URL, URL) {
        let fm = FileManager.default
        let localIPA = inputsDir.appendingPathComponent(ipaURL.lastPathComponent)
        let localP12 = inputsDir.appendingPathComponent(p12URL.lastPathComponent)
        let localProv = inputsDir.appendingPathComponent(provURL.lastPathComponent)
        [localIPA, localP12, localProv].forEach { dest in
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
        }
        try fm.copyItem(at: ipaURL, to: localIPA)
        try fm.copyItem(at: p12URL, to: localP12)
        try fm.copyItem(at: provURL, to: localProv)
        return (localIPA, localP12, localProv)
    }
   
    static func extractIPA(
        ipaURL: URL,
        to workDir: URL,
        progressUpdate: @escaping (String) -> Void
    ) throws {
        let fm = FileManager.default
        let progress = Progress()
        let observation = progress.observe(\Progress.fractionCompleted) { prog, _ in
            let pct = Int(prog.fractionCompleted * 100)
            progressUpdate("Unzipping IPA 🔓 (\(pct)%)")
        }
        defer {
            observation.invalidate()
        }
        try fm.unzipItem(at: ipaURL, to: workDir, progress: progress)
    }
   
    static func findAppBundle(in payloadDir: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: payloadDir.path) else {
            throw NSError(domain: "ProStoreTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "Payload not found"])
        }
        let contents = try fm.contentsOfDirectory(atPath: payloadDir.path)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw NSError(domain: "ProStoreTools", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle in Payload"])
        }
        return payloadDir.appendingPathComponent(appName)
    }
   
    static func createSignedIPA(
        from workDir: URL,
        originalIPAURL: URL,
        outputDir: URL,
        progressUpdate: @escaping (String) -> Void
    ) throws -> URL {
        let fm = FileManager.default
        let originalBase = originalIPAURL.deletingPathExtension().lastPathComponent
        let finalFileName = "\(originalBase)_signed_\(UUID().uuidString).ipa"
        let signedIpa = outputDir.appendingPathComponent(finalFileName)
        let progress = Progress()
        let observation = progress.observe(\Progress.fractionCompleted) { prog, _ in
            let pct = Int(prog.fractionCompleted * 100)
            progressUpdate("Zipping signed IPA 📦 (\(pct)%)")
        }
        defer {
            observation.invalidate()
        }
        try fm.zipItem(at: workDir, to: signedIpa, shouldKeepParent: false, progress: progress)
        // Copy to Documents for sharing
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outURL = docs.appendingPathComponent(finalFileName)
        if fm.fileExists(atPath: outURL.path) {
            try fm.removeItem(at: outURL)
        }
        try fm.copyItem(at: signedIpa, to: outURL)
        return outURL
    }
   
    static func cleanupTemporaryFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
