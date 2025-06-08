import XCTest
@testable import GPS_Logger
import SQLite3
import Compression

final class MBTilesVectorSourcePBFTests: XCTestCase {
    /// 簡単な PBF タイルを生成して MBTiles を作成
    private func makeMBTiles() throws -> URL {
        func varint(_ v: UInt64) -> Data {
            var value = v
            var data = Data()
            while true {
                let b = UInt8(value & 0x7F)
                value >>= 7
                if value != 0 {
                    data.append(b | 0x80)
                } else {
                    data.append(b)
                    break
                }
            }
            return data
        }
        func command(id: UInt32, count: UInt32) -> UInt32 {
            return (count << 3) | id
        }
        func zigzag(_ v: Int32) -> UInt32 {
            return UInt32(bitPattern: (v << 1) ^ (v >> 31))
        }

        // geometry: MoveTo(0,0) LineTo(10,10)
        var geom = Data()
        [command(id:1,count:1), zigzag(0), zigzag(0),
         command(id:2,count:1), zigzag(10), zigzag(10)].forEach { g in
            geom.append(varint(UInt64(g)))
        }

        // feature
        var feature = Data()
        feature.append(varint(UInt64((3 << 3) | 0)))
        feature.append(varint(UInt64(2))) // lineString
        feature.append(varint(UInt64((4 << 3) | 2)))
        feature.append(varint(UInt64(geom.count)))
        feature.append(geom)

        // layer
        let name = "layer"
        var layer = Data()
        layer.append(varint(UInt64((1 << 3) | 2)))
        layer.append(varint(UInt64(name.utf8.count)))
        layer.append(name.data(using: .utf8)!)
        layer.append(varint(UInt64((2 << 3) | 2)))
        layer.append(varint(UInt64(feature.count)))
        layer.append(feature)
        layer.append(varint(UInt64((5 << 3) | 0)))
        layer.append(varint(4096))

        // tile
        var tile = Data()
        tile.append(varint(UInt64((3 << 3) | 2)))
        tile.append(varint(UInt64(layer.count)))
        tile.append(layer)

        // gzip compress
        var encoded = Data(count: compression_encode_scratch_buffer_size(COMPRESSION_ZLIB))
        var out = Data(count: tile.count + 64)
        let result = out.withUnsafeMutableBytes { outPtr in
            tile.withUnsafeBytes { inPtr in
                compression_encode_buffer(outPtr.bindMemory(to: UInt8.self).baseAddress!, out.count,
                                           inPtr.bindMemory(to: UInt8.self).baseAddress!, tile.count,
                                           encoded.withUnsafeMutableBytes { $0.baseAddress },
                                           COMPRESSION_ZLIB)
            }
        }
        out.removeSubrange(result..<out.count)
        let pbf = out

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_pbf.mbtiles")
        var db: OpaquePointer? = nil
        sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        defer { if let db = db { sqlite3_close(db) } }
        sqlite3_exec(db, "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);", nil, nil, nil)
        var stmt: OpaquePointer? = nil
        sqlite3_prepare_v2(db, "INSERT INTO tiles VALUES (0,0,0,?)", -1, &stmt, nil)
        pbf.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(pbf.count), nil)
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return url
    }

    func testLoadPBF() throws {
        let url = try makeMBTiles()
        guard let src = MBTilesVectorSource(url: url, zoomLevel: 0) else {
            XCTFail("failed to open pbf mbtiles")
            return
        }
        let overlays = src.overlays(in: MKMapRect.world)
        XCTAssertEqual(overlays.count, 1)
    }
}
