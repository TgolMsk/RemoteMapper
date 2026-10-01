import Foundation

@main enum BinaryCaptureTests {
    static func record(_ payload: [UInt8], type: UInt8 = 3) -> Data {
        let size = UInt32(payload.count + 9)
        return Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255),
                     0, 0, 0, 1, 0, 0, 0, 1, type] + payload)
    }
    static func acl(_ data: [UInt8], handle: UInt16, continuation: Bool = false) -> Data {
        let flags = handle | (continuation ? 0x1000 : 0x2000)
        return record([UInt8(flags & 255), UInt8(flags >> 8), UInt8(data.count & 255), UInt8(data.count >> 8)] + data)
    }
    static func main() {
        // ATT 通知；两个连接交错分片，并将文件记录拆成单字节读取。
        let pdu: [UInt8] = [10, 0, 4, 0, 0x1b, 0x36, 0, 0, 0, 7, 0, 2, 0xb8, 1]
        let stream = acl(Array(pdu.prefix(8)), handle: 0x401)
            + acl(pdu, handle: 0x402)
            + acl(Array(pdu.dropFirst(8)), handle: 0x401, continuation: true)
        let reader = PklgVoiceExtractor()
        var frames: [RemoteVoiceFrame] = []
        for byte in stream { frames += reader.ingest(Data([byte])) }
        precondition(frames.count == 2)
        precondition(frames.map(\.connectionHandle) == ["0x0402", "0x0401"])
        precondition(frames.allSatisfy { $0.sequence == 7 && $0.attributeHandle == 0x36 && $0.opusPayload == Data([0xb8, 1]) })
        precondition(reader.recordsScanned == 3)
        precondition(PklgVoiceExtractor().ingest(acl(pdu, handle: 1, continuation: true)).isEmpty)
        precondition(PklgVoiceExtractor().ingest(record([1, 2, 3], type: 0)).isEmpty)
        var wrongCID = pdu; wrongCID[2] = 5
        precondition(PklgVoiceExtractor().ingest(acl(wrongCID, handle: 1)).isEmpty)
        precondition(PklgVoiceExtractor().ingest(stream.prefix(12)).isEmpty)
        precondition(PklgVoiceExtractor().ingest(Data([255, 255, 255, 255])).isEmpty)
        print("二进制捕获：交错连接、分片、部分记录及无效数据验证通过")
    }
}
