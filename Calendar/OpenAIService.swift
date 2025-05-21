import Foundation
import EventKit

final class OpenAIService {
    struct EventSuggestion: Decodable {
        let title: String
        let startDate: Date
        let endDate: Date
    }

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchSuggestions(for events: [EKEvent], completion: @escaping ([EventSuggestion]) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let eventDescriptions = events.map { event in
            "\(event.title ?? "(No Title)") from \(event.startDate) to \(event.endDate)"
        }.joined(separator: "\n")

        let prompt = "Here are my existing events:\n\(eventDescriptions)\nSuggest additional events for the upcoming week in JSON format as an array of {\"title\": String, \"startDate\": \"ISO8601\", \"endDate\": \"ISO8601\"}."

        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that schedules events."],
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion([])
            return
        }

        let task = session.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                completion([])
                return
            }

            struct ChatCompletionResponse: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable {
                        let content: String
                    }
                    let message: Message
                }
                let choices: [Choice]
            }

            do {
                let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                guard let content = response.choices.first?.message.content,
                      let suggestionsData = content.data(using: .utf8) else {
                    completion([])
                    return
                }
                let suggestions = try JSONDecoder().decode([EventSuggestion].self, from: suggestionsData)
                completion(suggestions)
            } catch {
                completion([])
            }
        }
        task.resume()
    }
}
