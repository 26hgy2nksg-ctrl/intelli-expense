import Foundation

public enum ExportArchiveError: Error, Equatable, Sendable {
    case archiveTooLarge
}

public struct ExportArchiveBuilder: Sendable {
    private let csvCommentRow: String
    private let manualEntryStub: ExportManualEntryStub
    private let filenameBuilder: ExportFilenameBuilder

    public init(
        csvCommentRow: String,
        manualEntryStub: ExportManualEntryStub,
        filenameBuilder: ExportFilenameBuilder = ExportFilenameBuilder()
    ) {
        self.csvCommentRow = csvCommentRow
        self.manualEntryStub = manualEntryStub
        self.filenameBuilder = filenameBuilder
    }

    public func archiveData(
        for receipts: [ExportReceipt],
        progress: ((ExportArchiveProgress) -> Void)? = nil
    ) throws -> Data {
        let sortedReceipts = ExportFormatting.sortedReceipts(receipts)
        progress?(ExportArchiveProgress(completedReceipts: 0, totalReceipts: sortedReceipts.count))
        var entries: [(path: String, data: Data)] = [
            (
                path: "summary.csv",
                data: SummaryCSVExporter(commentRow: csvCommentRow).csvData(for: sortedReceipts)
            )
        ]
        entries.append(contentsOf: try filenameBuilder.fileEntries(
            for: sortedReceipts,
            manualEntryStub: manualEntryStub
        ) { completedReceipts in
            progress?(ExportArchiveProgress(completedReceipts: completedReceipts, totalReceipts: sortedReceipts.count))
        })
        try Task.checkCancellation()
        return try StoredZipWriter().archive(entries: entries)
    }
}

private struct StoredZipWriter {
    func archive(entries: [(path: String, data: Data)]) throws -> Data {
        var output = Data()
        var centralDirectory = Data()
        var centralRecords: [CentralRecord] = []

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = try uint32(entry.data.count)
            let localHeaderOffset = try uint32(output.count)

            appendLocalHeader(
                to: &output,
                nameData: nameData,
                crc32: crc,
                compressedSize: size,
                uncompressedSize: size
            )
            output.append(entry.data)

            centralRecords.append(
                CentralRecord(
                    nameData: nameData,
                    crc32: crc,
                    compressedSize: size,
                    uncompressedSize: size,
                    localHeaderOffset: localHeaderOffset
                )
            )
        }

        let centralDirectoryOffset = try uint32(output.count)
        for record in centralRecords {
            appendCentralDirectoryRecord(record, to: &centralDirectory)
        }
        let centralDirectorySize = try uint32(centralDirectory.count)
        output.append(centralDirectory)

        appendEndOfCentralDirectory(
            to: &output,
            entryCount: try uint16(centralRecords.count),
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset
        )

        return output
    }

    private func appendLocalHeader(
        to data: inout Data,
        nameData: Data,
        crc32: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32
    ) {
        data.appendUInt32LE(0x04034B50)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0x0800)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(crc32)
        data.appendUInt32LE(compressedSize)
        data.appendUInt32LE(uncompressedSize)
        data.appendUInt16LE(UInt16(nameData.count))
        data.appendUInt16LE(0)
        data.append(nameData)
    }

    private func appendCentralDirectoryRecord(_ record: CentralRecord, to data: inout Data) {
        data.appendUInt32LE(0x02014B50)
        data.appendUInt16LE(20)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0x0800)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(record.crc32)
        data.appendUInt32LE(record.compressedSize)
        data.appendUInt32LE(record.uncompressedSize)
        data.appendUInt16LE(UInt16(record.nameData.count))
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(0)
        data.appendUInt32LE(record.localHeaderOffset)
        data.append(record.nameData)
    }

    private func appendEndOfCentralDirectory(
        to data: inout Data,
        entryCount: UInt16,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32
    ) {
        data.appendUInt32LE(0x06054B50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(entryCount)
        data.appendUInt16LE(entryCount)
        data.appendUInt32LE(centralDirectorySize)
        data.appendUInt32LE(centralDirectoryOffset)
        data.appendUInt16LE(0)
    }

    private func uint16(_ value: Int) throws -> UInt16 {
        guard value <= Int(UInt16.max) else {
            throw ExportArchiveError.archiveTooLarge
        }
        return UInt16(value)
    }

    private func uint32(_ value: Int) throws -> UInt32 {
        guard value <= Int(UInt32.max) else {
            throw ExportArchiveError.archiveTooLarge
        }
        return UInt32(value)
    }

    private struct CentralRecord {
        var nameData: Data
        var crc32: UInt32
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var localHeaderOffset: UInt32
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            var current = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                if current & 1 == 1 {
                    current = (current >> 1) ^ 0xEDB88320
                } else {
                    current >>= 1
                }
            }
            crc = (crc >> 8) ^ current
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value & 0xFF00) >> 8))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value & 0x0000FF00) >> 8))
        append(UInt8((value & 0x00FF0000) >> 16))
        append(UInt8((value & 0xFF000000) >> 24))
    }
}
