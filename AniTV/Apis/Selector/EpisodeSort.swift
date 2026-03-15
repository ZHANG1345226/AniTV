
import Foundation
import Combine

// Placeholder for BigNum, adjust if more functionality is needed later.
struct BigNum {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }

    func toFloat() -> Float {
        return Float(value)
    }

    func isNegative() -> Bool {
        return value < 0
    }
}

enum EpisodeType: String, Codable, CaseIterable, Comparable {
    case mainStory = "MainStory"
    case sp = "SP"
    case op = "OP"
    case ed = "ED"
    case pv = "PV"
    case mad = "MAD"
    case ova = "OVA"
    case oad = "OAD"

    // Custom comparison to match Kotlin's implicit order
    static func < (lhs: EpisodeType, rhs: EpisodeType) -> Bool {
        // Define an explicit order matching the Kotlin `entries` order (implicit order of enum cases in Kotlin).
        // This order is derived from the order of `EpisodeType.entries` in Kotlin, which is the declaration order.
        let order: [EpisodeType] = [.mainStory, .sp, .op, .ed, .pv, .mad, .ova, .oad]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false // All cases should be in `order`
        }
        return lhsIndex < rhsIndex
    }
}

enum EpisodeSort: Codable, Comparable, CustomStringConvertible {
    case normal(number: Float)
    case special(type: EpisodeType, number: Float?)
    case unknown(raw: String)

    var number: Float? {
        switch self {
        case .normal(let num): return num
        case .special(_, let num): return num
        case .unknown: return nil
        }
    }

    var raw: String {
        switch self {
        case .normal(let num):
            return String(format: num.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", num)
        case .special(let type, let num):
            if let num = num {
                let numStr = String(format: num.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", num)
                return "\(type.rawValue)\(numStr)"
            }
            return type.rawValue
        case .unknown(let rawValue): return rawValue
        }
    }

    var description: String {
        switch self {
        case .normal(let num):
            return String(format: num.truncatingRemainder(dividingBy: 1) == 0 ? "%02.0f" : "%.1f", num)
        case .special(_, _):
            return raw // Kotlin's toString for Special is raw
        case .unknown(let rawValue):
            return rawValue
        }
    }

    var isPartial: Bool {
        if case .normal(let num) = self {
            return num.truncatingRemainder(dividingBy: 1) == 0.5
        }
        return false
    }

    // MARK: - Comparable

    static func < (lhs: EpisodeSort, rhs: EpisodeSort) -> Bool {
        // Kotlin's compareTo logic: Normal < Special < Unknown
        switch (lhs, rhs) {
        case (.normal(let lNum), .normal(let rNum)):
            return lNum < rNum
        case (.normal, .special), (.normal, .unknown):
            return true
        case (.special(let lType, let lNum), .special(let rType, let rNum)):
            let typeComparison = lType < rType
            if typeComparison { return true }
            if lType > rType { return false } // types are equal or lType > rType
            
            // Types are equal, compare numbers
            switch (lNum, rNum) {
            case (nil, nil): return false // Equal
            case (nil, _): return true // nil < non-nil
            case (_, nil): return false // non-nil > nil
            case (let ln, let rn): return ln! < rn!
            }
        case (.special, .unknown):
            return true
        case (.special, .normal): // Special > Normal
            return false
        case (.unknown, .normal), (.unknown, .special): // Unknown > Normal, Unknown > Special
            return false
        case (.unknown(let lRaw), .unknown(let rRaw)):
            return lRaw < rRaw
        default:
            return false // All other combination of cases
        }
    }

    static func == (lhs: EpisodeSort, rhs: EpisodeSort) -> Bool {
        // Based on Kotlin's final override fun equals(other: Any?): Boolean
        // if (otherFloat != thisFloat) return false
        // return other.raw == raw
        guard lhs.number == rhs.number else { return false }
        return lhs.raw == rhs.raw
    }

    // MARK: - Initializers

    init(_ raw: String) {
        if let floatValue = Float(raw), floatValue >= 0 {
            if floatValue.truncatingRemainder(dividingBy: 1) == 0 || floatValue.truncatingRemainder(dividingBy: 1) == 0.5 {
                self = .normal(number: floatValue)
                return
            }
        }

        // Try to parse as special
        if let type = EpisodeType.allCases.first(where: { raw.starts(with: $0.rawValue) }) {
            let numString = raw.dropFirst(type.rawValue.count)
            if numString.isEmpty {
                self = .special(type: type, number: nil)
                return
            }
            if let num = Float(numString), num >= 0 {
                // Kotlin's getSpecialByRaw allows .5 floats or integers
                if num.truncatingRemainder(dividingBy: 1) == 0 || num.truncatingRemainder(dividingBy: 1) == 0.5 {
                    self = .special(type: type, number: num)
                    return
                }
            }
        }

        self = .unknown(raw: raw)
    }

    init(_ int: Int, type: EpisodeType? = .mainStory) {
        self.init(BigNum(int), type: type)
    }

    init(_ bigNum: BigNum, type: EpisodeType? = .mainStory) {
        if bigNum.isNegative() {
            self = .unknown(raw: bigNum.value.description)
            return
        }
        let float = bigNum.toFloat()
        if (float.truncatingRemainder(dividingBy: 1) != 0 && float.truncatingRemainder(dividingBy: 1) != 0.5) {
            self = .unknown(raw: bigNum.value.description)
            return
        }

        switch type {
        case .mainStory:
            self = .normal(number: float)
        case .sp, .op, .ed, .pv, .mad, .ova, .oad:
            self = .special(type: type!, number: float)
        case .none:
            self = .unknown(raw: bigNum.value.description)
        }
    }
    
    // MARK: - Codable
    // Custom Codable implementation to match Kotlin's serialization.
    // Kotlin uses @ProtoNumber and @SerialName, for Swift, we'll try to mimic the structure.
    // Given the Kotlin code, it seems to flatten the fields.
    // We will serialize as an object with a "type" field and relevant data.
    
    enum CodingKeys: String, CodingKey {
        case type
        case number
        case raw
    }

    enum EpisodeSortTypeDiscriminator: String, Codable {
        case Normal
        case Special
        case Unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .normal(let num):
            try container.encode(EpisodeSortTypeDiscriminator.Normal.rawValue, forKey: .type)
            try container.encode(num, forKey: .number)
        case .special(let type, let num):
            try container.encode(EpisodeSortTypeDiscriminator.Special.rawValue, forKey: .type)
            try container.encode(type.rawValue, forKey: .type) // Encode the EpisodeType rawValue again as "type"
            try container.encodeIfPresent(num, forKey: .number)
        case .unknown(let rawValue):
            try container.encode(EpisodeSortTypeDiscriminator.Unknown.rawValue, forKey: .type)
            try container.encode(rawValue, forKey: .raw)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeDiscriminatorString = try container.decode(String.self, forKey: .type)

        if typeDiscriminatorString == EpisodeSortTypeDiscriminator.Normal.rawValue {
            let number = try container.decode(Float.self, forKey: .number)
            self = .normal(number: number)
        } else if let episodeType = EpisodeType(rawValue: typeDiscriminatorString) { // Check if it's a valid EpisodeType rawValue
            let number = try container.decodeIfPresent(Float.self, forKey: .number)
            self = .special(type: episodeType, number: number)
        } else { // Fallback to unknown if it's not Normal or a known EpisodeType
            let rawValue = try container.decode(String.self, forKey: .raw)
            self = .unknown(raw: rawValue)
        }
    }
}
