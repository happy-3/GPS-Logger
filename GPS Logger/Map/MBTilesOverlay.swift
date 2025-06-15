import Foundation
import MapKit
import SQLite3
import os

/// MBTiles ファイルからタイル画像を読み込む MKTileOverlay の実装
final class MBTilesOverlay: MKTileOverlay {
    private let db: OpaquePointer?
    private var stmt: OpaquePointer?
    private let queue = DispatchQueue(label: "MBTilesOverlay.DB")

    init?(mbtilesURL: URL) {
        var handle: OpaquePointer? = nil
        if sqlite3_open_v2(mbtilesURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            return nil
        }
        self.db = handle
        let query = "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?"
        if sqlite3_prepare_v2(handle, query, -1, &stmt, nil) != SQLITE_OK {
            sqlite3_close(handle)
            return nil
        }
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 1
        maximumZ = 18
    }

    deinit {
        if let handle = db {
            sqlite3_close(handle)
        }
        if let s = stmt {
            sqlite3_finalize(s)
        }
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        queue.async {
            guard let handle = self.db, let stmt = self.stmt else {
                result(nil, NSError(domain: "MBTiles", code: 1))
                return
            }

            let row = Int(pow(2.0, Double(path.z))) - 1 - path.y
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_int(stmt, 1, Int32(path.z))
            sqlite3_bind_int(stmt, 2, Int32(path.x))
            sqlite3_bind_int(stmt, 3, Int32(row))

            if sqlite3_step(stmt) == SQLITE_ROW {
                if let bytes = sqlite3_column_blob(stmt, 0) {
                    let size = sqlite3_column_bytes(stmt, 0)
                    let data = Data(bytes: bytes, count: Int(size))
                    result(data, nil)
                } else {
                    result(nil, NSError(domain: "MBTiles", code: 3))
                }
            } else {
                result(nil, NSError(domain: "MBTiles", code: 4))
            }
            sqlite3_reset(stmt)
        }
    }
}
