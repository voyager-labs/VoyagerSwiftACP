import Foundation

extension PostFilterEvaluator {
    func batchedNSURLSymbols(from specs: [ConditionSpec]) -> Set<String> {
        var symbols: Set<String> = []

        for spec in specs {
            for key in spec.orderedSystemKeys where key.prefix == "nsurl" {
                symbols.insert(key.symbol)
            }
        }

        return symbols
    }

    func preloadNSURLResourceValues(
        symbols: Set<String>,
        context: inout PathContext,
    ) {
        guard symbols.isEmpty == false else {
            return
        }

        let keys = Set(symbols.map(URLResourceKey.init(rawValue:)))

        do {
            let values = try context.url.resourceValues(forKeys: keys)
            for symbol in symbols {
                let key = URLResourceKey(rawValue: symbol)
                if let value = values.allValues[key] {
                    context.resourceCache[symbol] = .value(value)
                } else {
                    context.resourceCache[symbol] = .missing
                }
            }
        } catch {
            for symbol in symbols where context.resourceCache[symbol] == nil {
                context.resourceCache[symbol] = .missing
            }
        }
    }
}
