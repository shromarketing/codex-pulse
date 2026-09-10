import Foundation

enum CodexTaskRouteAdvisorError: LocalizedError {
    case codexUnavailable
    case invalidResponse
    case commandFailed

    var errorDescription: String? {
        switch self {
        case .codexUnavailable: "Codex is not connected"
        case .invalidResponse: "Codex returned an invalid route"
        case .commandFailed: "Codex could not analyze the task"
        }
    }
}

struct CodexTaskRouteAdvisor: Sendable {
    func analyze(task: String) async throws -> CodexRouteAssessment {
        guard let executable = ExecutableLocator.locate("codex") else {
            throw CodexTaskRouteAdvisorError.codexUnavailable
        }

        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("codex-pulse-router-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let schemaURL = workingDirectory.appendingPathComponent("route.schema.json")
        let schemaData = try JSONSerialization.data(withJSONObject: Self.responseSchema(), options: [.sortedKeys])
        try schemaData.write(to: schemaURL, options: [.atomic])

        let result = try await CommandRunner.run(
            executable: executable,
            arguments: [
                "exec",
                "--ephemeral",
                "--skip-git-repo-check",
                "--ignore-user-config",
                "--ignore-rules",
                "--sandbox", "read-only",
                "--model", "gpt-5.6-luna",
                "--config", "model_reasoning_effort=\"low\"",
                "--output-schema", schemaURL.path,
                "--color", "never",
                "-",
            ],
            input: Self.prompt(task: String(task.prefix(4_000))),
            timeout: 45,
            currentDirectoryURL: workingDirectory
        )

        guard result.exitCode == 0 else { throw CodexTaskRouteAdvisorError.commandFailed }
        guard let payload = Self.jsonPayload(from: result.stdout),
              let response = try? JSONDecoder().decode(Response.self, from: payload),
              let model = RouterModel(rawValue: response.model),
              let effort = ReasoningEffort(rawValue: response.effort),
              let confidence = RouterConfidence(rawValue: response.confidence),
              let taskShape = RouterTaskShape(rawValue: response.taskShape)
        else {
            throw CodexTaskRouteAdvisorError.invalidResponse
        }

        let stages = response.stages.compactMap { stage -> RouteStage? in
            guard let model = RouterModel(rawValue: stage.model),
                  let effort = ReasoningEffort(rawValue: stage.effort)
            else { return nil }
            return RouteStage(
                model: model,
                effort: effort,
                titleRU: String(stage.titleRU.prefix(220)),
                titleEN: String(stage.titleEN.prefix(220))
            )
        }

        return CodexRouteAssessment(
            model: model,
            effort: effort,
            confidence: confidence,
            taskShape: taskShape,
            needsSplit: response.needsSplit,
            rationaleRU: String(response.rationaleRU.prefix(700)),
            rationaleEN: String(response.rationaleEN.prefix(700)),
            stages: Array(stages.prefix(4))
        )
    }

    static func decodeForTesting(_ value: String) -> CodexRouteAssessment? {
        guard let payload = jsonPayload(from: value),
              let response = try? JSONDecoder().decode(Response.self, from: payload),
              let model = RouterModel(rawValue: response.model),
              let effort = ReasoningEffort(rawValue: response.effort),
              let confidence = RouterConfidence(rawValue: response.confidence),
              let taskShape = RouterTaskShape(rawValue: response.taskShape)
        else { return nil }

        let stages = response.stages.compactMap { stage -> RouteStage? in
            guard let model = RouterModel(rawValue: stage.model),
                  let effort = ReasoningEffort(rawValue: stage.effort)
            else { return nil }
            return RouteStage(model: model, effort: effort, titleRU: stage.titleRU, titleEN: stage.titleEN)
        }
        return CodexRouteAssessment(
            model: model,
            effort: effort,
            confidence: confidence,
            taskShape: taskShape,
            needsSplit: response.needsSplit,
            rationaleRU: response.rationaleRU,
            rationaleEN: response.rationaleEN,
            stages: stages
        )
    }

    private struct Response: Decodable {
        let model: String
        let effort: String
        let confidence: String
        let taskShape: String
        let needsSplit: Bool
        let rationaleRU: String
        let rationaleEN: String
        let stages: [Stage]

        enum CodingKeys: String, CodingKey {
            case model, effort, confidence, stages
            case taskShape = "task_shape"
            case needsSplit = "needs_split"
            case rationaleRU = "rationale_ru"
            case rationaleEN = "rationale_en"
        }
    }

    private struct Stage: Decodable {
        let model: String
        let effort: String
        let titleRU: String
        let titleEN: String

        enum CodingKeys: String, CodingKey {
            case model, effort
            case titleRU = "title_ru"
            case titleEN = "title_en"
        }
    }

    private static func prompt(task: String) -> String {
        """
        You are a routing classifier inside Codex Pulse. Analyze the task, but do not perform it and do not use tools.

        Current official model roles:
        - Luna: efficient for simple, latency-sensitive, cost-sensitive, or high-volume repeatable work once the workflow is known.
        - Terra: balanced intelligence and cost for normal professional coding, research, design, documents, and planning.
        - Sol: frontier capability for genuinely difficult, high-stakes, architectural, security-sensitive, or deeply ambiguous professional work.

        Reasoning effort:
        - low for narrow, clear tasks;
        - medium as the balanced default;
        - high only when planning, ambiguity, dependencies, verification, or risk create a clear quality gain;
        - xhigh only for exceptionally difficult quality-first work.

        Route the NEXT useful stage, not an entire large project as one opaque action. Consider ambiguity, stakes, external tools and I/O, numeric scale, reversibility, verification, and whether the task should be split. A task such as analyzing hundreds of sites and downloading gigabytes should normally be split into planning/sample, repeatable batch execution, and verification. Do not estimate an exact token count. Do not claim that a provider will complete an action automatically.

        Return concise Russian and English rationales. If needs_split is true, return 2-4 concrete stages and choose a model/effort for each. Otherwise return an empty stages array. Confidence means confidence in the route given the amount of task detail.

        Task:
        <task>\(task)</task>
        """
    }

    private static func jsonPayload(from output: String) -> Data? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}")
        else { return nil }
        return String(trimmed[start...end]).data(using: .utf8)
    }

    private static func responseSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
            "model": ["type": "string", "enum": ["Luna", "Terra", "Sol"]],
            "effort": ["type": "string", "enum": ["low", "medium", "high", "xhigh"]],
            "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
            "task_shape": ["type": "string", "enum": ["quick", "writing", "research", "coding", "design", "documents", "automation", "architecture", "review", "other"]],
            "needs_split": ["type": "boolean"],
            "rationale_ru": ["type": "string"],
            "rationale_en": ["type": "string"],
            "stages": [
                "type": "array",
                "maxItems": 4,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "model": ["type": "string", "enum": ["Luna", "Terra", "Sol"]],
                        "effort": ["type": "string", "enum": ["low", "medium", "high", "xhigh"]],
                        "title_ru": ["type": "string"],
                        "title_en": ["type": "string"],
                    ],
                    "required": ["model", "effort", "title_ru", "title_en"],
                ],
            ],
        ],
            "required": ["model", "effort", "confidence", "task_shape", "needs_split", "rationale_ru", "rationale_en", "stages"],
        ]
    }
}
