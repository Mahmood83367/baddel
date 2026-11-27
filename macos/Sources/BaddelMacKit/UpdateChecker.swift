import BaddelCore
import Foundation

/// Asks GitHub which releases of Baddel exist. This is the only network request
/// the app can make, and it happens only when the user chooses "Check for
/// Updates…" or has turned on the daily check. It sends nothing about the user
/// or their text: one anonymous GET of the public release list. Nothing is
/// downloaded or installed.
public enum UpdateChecker {
    public enum Outcome: Equatable {
        case result(UpdateCheckResult)
        case failed
    }

    public static func check(current: String, channel: UpdateChannel, completion: @escaping (Outcome) -> Void) {
        guard let url = URL(string: UpdateCheck.releasesAPI) else { return completion(.failed) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Baddel/\(current)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        URLSession(configuration: configuration).dataTask(with: request) { data, response, _ in
            let outcome: Outcome
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4 * 1024 * 1024,
               let result = UpdateCheck.evaluate(releasesJSON: data, current: current, channel: channel) {
                outcome = .result(result)
            } else {
                outcome = .failed
            }
            DispatchQueue.main.async { completion(outcome) }
        }.resume()
    }
}
