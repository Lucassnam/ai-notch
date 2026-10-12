import Foundation

struct ModelPrice: Hashable, Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double

    func cost(for tokens: TokenBreakdown) -> Double {
        let million = 1_000_000.0
        return (
            Double(tokens.input) * input
                + Double(tokens.output) * output
                + Double(tokens.cacheRead) * cacheRead
                + Double(tokens.cacheWrite5m) * cacheWrite5m
                + Double(tokens.cacheWrite1h) * cacheWrite1h
        ) / million
    }
}

struct PricingCatalog: Sendable {
    let pricingDate: Date

    init(pricingDate: Date = Date()) {
        self.pricingDate = pricingDate
    }

    func price(provider: ProviderID, model rawModel: String) -> ModelPrice {
        let model = rawModel.lowercased()

        switch provider {
        case .claude:
            if model.contains("fable") || model.contains("mythos") {
                return anthropic(input: 10, output: 50)
            }
            if model.contains("opus") {
                return anthropic(input: 5, output: 25)
            }
            if model.contains("sonnet-5") || model.contains("sonnet_5") {
                let launchPriceEnds = Calendar(identifier: .gregorian).date(
                    from: DateComponents(year: 2026, month: 9, day: 1)
                ) ?? .distantPast
                return pricingDate < launchPriceEnds
                    ? anthropic(input: 2, output: 10)
                    : anthropic(input: 3, output: 15)
            }
            if model.contains("haiku") {
                return anthropic(input: 1, output: 5)
            }
            return anthropic(input: 3, output: 15)

        case .codex:
            if model.contains("terra") {
                return openAI(input: 2.5, output: 15)
            }
            if model.contains("luna") {
                return openAI(input: 1, output: 6)
            }
            if model.contains("5.5") {
                return openAI(input: 1.25, output: 7.5)
            }
            return openAI(input: 5, output: 30)
        }
    }

    func estimatedCost(for event: UsageEvent) -> Double {
        price(provider: event.provider, model: event.model).cost(for: event.tokens)
    }

    private func anthropic(input: Double, output: Double) -> ModelPrice {
        ModelPrice(
            input: input,
            output: output,
            cacheRead: input * 0.1,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: input * 2
        )
    }

    private func openAI(input: Double, output: Double) -> ModelPrice {
        ModelPrice(
            input: input,
            output: output,
            cacheRead: input * 0.1,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: input * 1.25
        )
    }
}
