import Foundation

enum WebAppFaviconLoader {
    static func loadFaviconData(for websiteURL: URL) async -> Data? {
        let session = makeSession()
        let candidateURLs = await resolveCandidateURLs(for: websiteURL, session: session)
        var visitedURLs = Set<String>()

        for candidateURL in candidateURLs {
            guard visitedURLs.insert(normalizedCacheKey(for: candidateURL)).inserted else {
                continue
            }

            if let data = await fetchImageData(from: candidateURL, session: session) {
                return data
            }
        }

        return nil
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "NeatWebApp/1.0",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }

    private static func resolveCandidateURLs(for websiteURL: URL, session: URLSession) async -> [URL] {
        var candidates: [FaviconCandidate] = []

        if let page = await fetchHTML(from: websiteURL, session: session) {
            candidates.append(contentsOf: parseIconLinks(in: page.html, baseURL: page.url))
            candidates.append(contentsOf: fallbackCandidates(for: page.url))
        }

        candidates.append(contentsOf: fallbackCandidates(for: websiteURL))

        return candidates
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.url.absoluteString < rhs.url.absoluteString
                }

                return lhs.score > rhs.score
            }
            .map(\.url)
    }

    private static func fetchHTML(from url: URL, session: URLSession) async -> (url: URL, html: String)? {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                return nil
            }

            let html = String(decoding: data, as: UTF8.self)
            return (response.url ?? url, html)
        } catch {
            return nil
        }
    }

    private static func fetchImageData(from url: URL, session: URLSession) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            guard (200 ..< 300).contains(httpResponse.statusCode), !data.isEmpty else {
                return nil
            }

            if let mimeType = response.mimeType?.lowercased() {
                let isSupportedImage = mimeType.hasPrefix("image/")
                    || mimeType == "application/octet-stream"
                    || mimeType == "binary/octet-stream"
                guard isSupportedImage else {
                    return nil
                }
            }

            return data
        } catch {
            return nil
        }
    }

    private static func parseIconLinks(in html: String, baseURL: URL) -> [FaviconCandidate] {
        let htmlNSString = html as NSString
        let htmlRange = NSRange(html.startIndex..., in: html)
        guard let linkRegex = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        return linkRegex.matches(in: html, options: [], range: htmlRange).compactMap { match in
            let tag = htmlNSString.substring(with: match.range)
            guard
                let relValue = extractAttribute(named: "rel", from: tag)?.lowercased(),
                relValue.contains("icon"),
                let hrefValue = extractAttribute(named: "href", from: tag),
                let url = URL(string: hrefValue, relativeTo: baseURL)?.absoluteURL
            else {
                return nil
            }

            return FaviconCandidate(
                url: url,
                score: scoreForIconTag(
                    relValue: relValue,
                    hrefValue: hrefValue,
                    sizesValue: extractAttribute(named: "sizes", from: tag)
                )
            )
        }
    }

    private static func extractAttribute(named name: String, from tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\b\(escapedName)\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)'|([^'\"\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }

        let tagNSString = tag as NSString
        for groupIndex in 1 ..< match.numberOfRanges {
            let groupRange = match.range(at: groupIndex)
            guard groupRange.location != NSNotFound else {
                continue
            }

            return tagNSString.substring(with: groupRange)
        }

        return nil
    }

    private static func scoreForIconTag(relValue: String, hrefValue: String, sizesValue: String?) -> Int {
        var score = 0

        if relValue.contains("apple-touch-icon") {
            score += 320
        } else if relValue.contains("shortcut icon") {
            score += 280
        } else if relValue.contains("icon") {
            score += 240
        }

        if relValue.contains("mask-icon") {
            score -= 120
        }

        let normalizedHref = hrefValue.lowercased()
        if normalizedHref.hasSuffix(".png") {
            score += 90
        } else if normalizedHref.hasSuffix(".ico") {
            score += 70
        } else if normalizedHref.hasSuffix(".jpg") || normalizedHref.hasSuffix(".jpeg") {
            score += 50
        } else if normalizedHref.hasSuffix(".svg") {
            score += 10
        }

        if let sizesValue {
            score += iconSizeScore(from: sizesValue)
        }

        return score
    }

    private static func iconSizeScore(from value: String) -> Int {
        let lowercaseValue = value.lowercased()
        if lowercaseValue == "any" {
            return 64
        }

        let parsedSizes: [Int] = lowercaseValue.split(separator: " ").compactMap { candidate in
            let dimensions = candidate.split(separator: "x")
            guard
                dimensions.count == 2,
                let width = Int(dimensions[0]),
                let height = Int(dimensions[1])
            else {
                return nil
            }

            return max(width, height)
        }

        return parsedSizes.max() ?? 0
    }

    private static func fallbackCandidates(for url: URL) -> [FaviconCandidate] {
        guard let originURL = url.originURL else {
            return []
        }

        let fallbackPaths = [
            ("apple-touch-icon.png", 160),
            ("favicon.ico", 120)
        ]

        return fallbackPaths.compactMap { path, score in
            guard let fallbackURL = URL(string: path, relativeTo: originURL)?.absoluteURL else {
                return nil
            }

            return FaviconCandidate(url: fallbackURL, score: score)
        }
    }

    private static func normalizedCacheKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }
}

private struct FaviconCandidate {
    let url: URL
    let score: Int
}

private extension URL {
    var originURL: URL? {
        guard let scheme, let host else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/"
        return components.url
    }
}
