import Foundation
import MapKit
import Compression

/// Mapbox Vector Tile を簡易的に解析するパーサ
struct VectorTileParser {
    struct Feature {
        enum GeometryType: Int {
            case unknown = 0
            case point = 1
            case lineString = 2
            case polygon = 3
        }
        let type: GeometryType
        let geometry: [[(Int, Int)]]
    }

    struct Layer {
        let name: String
        let extent: Int
        let features: [Feature]
    }

    let layers: [Layer]

    static func parse(data: Data) -> VectorTileParser? {
        guard let raw = decompressIfNeeded(data) else { return nil }
        var reader = ProtoReader(data: raw)
        var layers: [Layer] = []
        while !reader.isAtEnd {
            guard let key = reader.readVarint() else { break }
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            if field == 3 && wire == 2, let ld = reader.readLengthDelimited() {
                if let layer = parseLayer(data: ld) { layers.append(layer) }
            } else {
                reader.skip(wire: wire)
            }
        }
        return VectorTileParser(layers: layers)
    }

    private static func decompressIfNeeded(_ data: Data) -> Data? {
        if data.starts(with: [0x1f, 0x8b]) {
            return gunzip(data)
        }
        return data
    }

    private static func gunzip(_ data: Data) -> Data? {
        var destSize = 1_000_000
        let maxSize = 20_000_000
        while destSize <= maxSize {
            var dest = Data(count: destSize)
            let result = dest.withUnsafeMutableBytes { destPtr in
                data.withUnsafeBytes { srcPtr in
                    compression_decode_buffer(destPtr.bindMemory(to: UInt8.self).baseAddress!,
                                              destSize,
                                              srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                                              data.count,
                                              nil,
                                              COMPRESSION_ZLIB)
                }
            }
            if result > 0 {
                dest.removeSubrange(result..<dest.count)
                return dest
            }
            destSize *= 2
        }
        return nil
    }

    private static func parseLayer(data: Data) -> Layer? {
        var reader = ProtoReader(data: data)
        var name = ""
        var extent = 4096
        var features: [Feature] = []
        while !reader.isAtEnd {
            guard let key = reader.readVarint() else { break }
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            switch field {
            case 1: // name
                if let d = reader.readLengthDelimited(), let s = String(data: d, encoding: .utf8) {
                    name = s
                }
            case 2: // features
                if let d = reader.readLengthDelimited(), let f = parseFeature(data: d) {
                    features.append(f)
                }
            case 5: // extent
                if let v = reader.readVarint() { extent = Int(v) }
            default:
                reader.skip(wire: wire)
            }
        }
        return Layer(name: name, extent: extent, features: features)
    }

    private static func parseFeature(data: Data) -> Feature? {
        var reader = ProtoReader(data: data)
        var typeRaw: Int = 0
        var geometryInts: [UInt32] = []
        while !reader.isAtEnd {
            guard let key = reader.readVarint() else { break }
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            switch field {
            case 3:
                if let v = reader.readVarint() { typeRaw = Int(v) }
            case 4:
                guard let len = reader.readVarint() else { return nil }
                let end = reader.offset + Int(len)
                while reader.offset < end {
                    if let v = reader.readVarint() { geometryInts.append(UInt32(v)) } else { break }
                }
            default:
                reader.skip(wire: wire)
            }
        }
        let type = Feature.GeometryType(rawValue: typeRaw) ?? .unknown
        let geom = decodeGeometry(geometryInts)
        return Feature(type: type, geometry: geom)
    }

    private static func decodeGeometry(_ ints: [UInt32]) -> [[(Int, Int)]] {
        var result: [[(Int, Int)]] = []
        var ring: [(Int, Int)] = []
        var x = 0
        var y = 0
        var i = 0
        while i < ints.count {
            let cmd = ints[i] & 0x7
            let count = Int(ints[i] >> 3)
            i += 1
            switch cmd {
            case 1: // MoveTo
                if !ring.isEmpty { result.append(ring); ring.removeAll() }
                for _ in 0..<count {
                    let dx = zigZagDecode(ints[i]);
                    let dy = zigZagDecode(ints[i+1]);
                    i += 2
                    x += dx; y += dy
                    ring.append((x,y))
                }
            case 2: // LineTo
                for _ in 0..<count {
                    let dx = zigZagDecode(ints[i]);
                    let dy = zigZagDecode(ints[i+1]);
                    i += 2
                    x += dx; y += dy
                    ring.append((x,y))
                }
            case 7: // ClosePath
                if !ring.isEmpty { result.append(ring); ring.removeAll() }
            default:
                break
            }
        }
        if !ring.isEmpty { result.append(ring) }
        return result
    }

    private static func zigZagDecode(_ n: UInt32) -> Int {
        return Int((n >> 1) ^ (~(n & 1) + 1))
    }
}

private struct ProtoReader {
    let data: Data
    var offset: Int = 0

    var isAtEnd: Bool { offset >= data.count }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let b = data[offset]; offset += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func readLengthDelimited() -> Data? {
        guard let len = readVarint() else { return nil }
        guard offset + Int(len) <= data.count else { return nil }
        let sub = data[offset..<offset+Int(len)]
        offset += Int(len)
        return Data(sub)
    }

    mutating func skip(wire: Int) {
        switch wire {
        case 0:
            _ = readVarint()
        case 1:
            offset += 8
        case 2:
            if let len = readVarint() { offset += Int(len) }
        case 5:
            offset += 4
        default:
            break
        }
    }
}
