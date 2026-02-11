import Foundation
import StructuredQueries

@Table("files")
struct FilterSearchEntryTable: Sendable {
    @Column("id")
    var id: Int64?
    @Column("directory_id")
    var directoryId: Int64?
    @Column("path")
    var path: String
    @Column("dir_path")
    var dirPath: String
    @Column("name_full")
    var nameFull: String
    @Column("extension")
    var fileExtension: String
    @Column("size")
    var size: Int64
    @Column("file_kind")
    var fileKind: String?
    @Column("modification_date")
    var modificationDate: Date
    @Column("original_metadata")
    var originalMetadata: String
}
