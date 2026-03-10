import Foundation

struct ServerSentEvent: Equatable, Sendable {
    let event: String?
    let data: String
    let id: String?
    let retryMilliseconds: Int?
}

struct ServerSentEventParser {
    func parse(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<ServerSentEvent, Error> {
        parse(lines: bytes.lines)
    }

    func parse<S: AsyncSequence & Sendable>(lines: S) -> AsyncThrowingStream<ServerSentEvent, Error>
    where S.Element == String {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var dataLines: [String] = []
                    var eventName: String?
                    var eventID: String?
                    var retryMilliseconds: Int?

                    for try await rawLine in lines {
                        let line = rawLine.trimmingCharacters(in: .newlines)

                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                continuation.yield(
                                    ServerSentEvent(
                                        event: eventName,
                                        data: dataLines.joined(separator: "\n"),
                                        id: eventID,
                                        retryMilliseconds: retryMilliseconds
                                    )
                                )
                            }
                            dataLines.removeAll(keepingCapacity: true)
                            eventName = nil
                            eventID = nil
                            retryMilliseconds = nil
                            continue
                        }

                        if line.hasPrefix(":") {
                            continue
                        }

                        let components = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                        let field = String(components[0])
                        let value: String
                        if components.count == 2 {
                            value = String(components[1]).trimmingCharacters(in: .whitespaces)
                        } else {
                            value = ""
                        }

                        switch field {
                        case "data":
                            dataLines.append(value)
                        case "event":
                            eventName = value
                        case "id":
                            eventID = value
                        case "retry":
                            retryMilliseconds = Int(value)
                        default:
                            break
                        }
                    }

                    if !dataLines.isEmpty {
                        continuation.yield(
                            ServerSentEvent(
                                event: eventName,
                                data: dataLines.joined(separator: "\n"),
                                id: eventID,
                                retryMilliseconds: retryMilliseconds
                            )
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
