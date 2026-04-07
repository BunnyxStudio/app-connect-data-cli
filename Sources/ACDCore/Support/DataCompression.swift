//
//  DataCompression.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import Foundation
import zlib

public enum GzipDataError: Error {
    case inflateInitFailed(Int32)
    case inflateFailed(Int32)
}

public extension Data {
    var isGzipData: Bool {
        count >= 2 && self[startIndex] == 0x1f && self[index(startIndex, offsetBy: 1)] == 0x8b
    }

    func gunzipped() throws -> Data {
        guard !isEmpty else { return Data() }

        var stream = z_stream()
        var status: Int32 = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw GzipDataError.inflateInitFailed(status)
        }
        defer { inflateEnd(&stream) }

        let bufferSize = 64 * 1024
        var outputData = Data()

        try withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) in
            guard let srcBase = srcBuffer.baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(srcBuffer.count)

            var outputBuffer = [UInt8](repeating: 0, count: bufferSize)
            repeat {
                status = outputBuffer.withUnsafeMutableBytes { dstBuffer in
                    stream.next_out = dstBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(bufferSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                if status != Z_OK && status != Z_STREAM_END {
                    throw GzipDataError.inflateFailed(status)
                }

                let bytesWritten = bufferSize - Int(stream.avail_out)
                if bytesWritten > 0 {
                    outputData.append(outputBuffer, count: bytesWritten)
                }
            } while status != Z_STREAM_END
        }

        return outputData
    }
}
