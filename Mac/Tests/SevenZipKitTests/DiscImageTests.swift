// DiscImageTests.swift -- the disc-image formats after Iso7z (Mac/Core/Handlers): each test
// builds an image around a real ISO 9660 file system (made with hdiutil) and an audio track,
// opens it as 7-Zip does, and checks the tracks it shows and the bytes they extract to.

import Compression
import Foundation
import XCTest
@testable import SevenZipKit

final class DiscImageTests: XCTestCase {

    // MARK: - fixtures

    private var work: String = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        try SZCodecs.loadCodecs()
        work = (NSTemporaryDirectory() as NSString).appendingPathComponent("sz-disc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        addTeardownBlock { [work] in try? FileManager.default.removeItem(atPath: work) }
    }

    private func path(_ name: String) -> String { (work as NSString).appendingPathComponent(name) }

    /// A small ISO 9660 image holding hello.txt ("hello disc\n").
    private lazy var iso: Data = {
        let src = path("isosrc")
        try? FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        try? Data("hello disc\n".utf8).write(to: URL(fileURLWithPath: src + "/hello.txt"))
        let out = path("plain.iso")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["makehybrid", "-iso", "-joliet", "-quiet", "-o", out, src]
        try? p.run()
        p.waitUntilExit()
        return (try? Data(contentsOf: URL(fileURLWithPath: out))) ?? Data()
    }()

    /// Some "audio": 10 frames of a pattern.
    private let audio: Data = Data((0..<(2352 * 10)).map { UInt8(truncatingIfNeeded: $0 &* 7) })

    /// The ISO as raw Mode 1 sectors: sync, header (MSF + mode 1), data, zero EDC/ECC.
    private func rawMode1(_ cooked: Data, startLBA: Int = 0) -> Data {
        var out = Data()
        let sectors = cooked.count / 2048
        for i in 0..<sectors {
            var s = Data([0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00])
            let lba = startLBA + i + 150
            func bcd(_ v: Int) -> UInt8 { UInt8((v / 10) << 4 | (v % 10)) }
            s.append(contentsOf: [bcd(lba / 4500), bcd((lba / 75) % 60), bcd(lba % 75), 0x01])
            s.append(cooked.subdata(in: (i * 2048)..<((i + 1) * 2048)))
            s.append(Data(count: 288))
            out.append(s)
        }
        return out
    }

    private func write(_ data: Data, _ name: String) throws {
        try data.write(to: URL(fileURLWithPath: path(name)))
    }

    private func msf(_ frames: Int) -> String {
        String(format: "%02d:%02d:%02d", frames / 4500, (frames / 75) % 60, frames % 75)
    }

    // MARK: - opening and extracting

    private struct Listed { let name: String; let size: UInt64 }

    private func list(_ archive: String) throws -> [Listed] {
        let folder = try SZFolder.folder(forPath: archive, passwordDelegate: nil)
        try folder.loadItems()
        return (0..<folder.itemCount).map { Listed(name: folder.nameOfItem(at: $0), size: folder.sizeOfItem(at: $0)) }
    }

    /// Extracts the whole image into a fresh directory and returns it.
    private func extract(_ archive: String) throws -> String {
        let dest = path("out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        let o = SZExtractOptions()
        o.outputDirectory = dest
        o.outDirMode = .direct
        o.overwriteMode = .overwrite
        let result = try XCTUnwrap(SZArchiveExtractor.extractArchives(at: [archive], options: o, progress: nil))
        XCTAssertTrue(result.isOK, "\(archive): \(result.messages)")
        return dest
    }

    private func data(_ dir: String, _ name: String) -> Data {
        (try? Data(contentsOf: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(name)))) ?? Data()
    }

    /// The data track is the ISO byte for byte, and 7-Zip lists its file system; the audio track
    /// is a 44.1 kHz stereo WAV around the frames.
    private func checkDataAndAudio(_ archive: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let items = try list(archive)
        XCTAssertEqual(items.map(\.name), ["Track01.iso", "Track02.wav"], file: file, line: line)
        XCTAssertEqual(items.first?.size, UInt64(iso.count), file: file, line: line)
        XCTAssertEqual(items.last?.size, UInt64(audio.count + 44), file: file, line: line)
        let out = try extract(archive)
        XCTAssertEqual(data(out, "Track01.iso"), iso, "the user data of the Mode 1 sectors", file: file, line: line)
        let wav = data(out, "Track02.wav")
        XCTAssertEqual(wav.prefix(4), Data("RIFF".utf8), file: file, line: line)
        XCTAssertEqual(wav.subdata(in: 8..<16), Data("WAVEfmt ".utf8), file: file, line: line)
        XCTAssertEqual(wav.dropFirst(44), audio, file: file, line: line)
        // and the ISO opens in turn
        let inner = try list((out as NSString).appendingPathComponent("Track01.iso"))
        XCTAssertTrue(inner.contains { $0.name == "hello.txt" }, "\(inner.map(\.name))", file: file, line: line)
    }

    // MARK: - CUE/BIN

    func testCueWithOneBinOfTwoTracks() throws {
        XCTAssertGreaterThan(iso.count, 0, "hdiutil made no ISO")
        let raw = rawMode1(iso)
        try write(raw + audio, "game.bin")
        let sectors = raw.count / 2352
        try write(Data("""
            FILE "game.bin" BINARY
              TRACK 01 MODE1/2352
                INDEX 01 00:00:00
              TRACK 02 AUDIO
                INDEX 00 \(msf(sectors))
                INDEX 01 \(msf(sectors))
            """.utf8), "game.cue")
        try checkDataAndAudio(path("game.cue"))
    }

    func testCueWithABinPerTrack() throws {
        try write(rawMode1(iso), "Game (Track 1).bin")
        try write(audio, "Game (Track 2).bin")
        try write(Data("""
            REM a cue sheet as redump writes it
            FILE "Game (Track 1).bin" BINARY
              TRACK 01 MODE1/2352
                INDEX 01 00:00:00
            FILE "Game (Track 2).bin" BINARY
              TRACK 02 AUDIO
                INDEX 01 00:00:00
            """.utf8), "Game.cue")
        try checkDataAndAudio(path("Game.cue"))
    }

    func testCueWithCookedSectors() throws {
        try write(iso, "data.iso.bin")
        try write(Data("FILE \"data.iso.bin\" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n".utf8), "data.cue")
        let items = try list(path("data.cue"))
        XCTAssertEqual(items.map(\.name), ["Track01.iso"])
        XCTAssertEqual(data(try extract(path("data.cue")), "Track01.iso"), iso)
    }

    /// The cue sheet opens (it is one), shows no track, and names the missing file in the
    /// archive's error -- clearer than "cannot open the file as an archive".
    func testCueWithAMissingBinSaysSo() throws {
        try write(Data("FILE \"gone.bin\" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n".utf8), "gone.cue")
        let folder = try SZFolder.folder(forPath: path("gone.cue"), passwordDelegate: nil)
        try folder.loadItems()
        XCTAssertEqual(folder.itemCount, 0)
        let props = try XCTUnwrap(folder.arcProps)
        let texts = (0..<props.levelCount).map { props.displayString(atLevel: $0, propID: .error) }
        XCTAssertTrue(texts.contains { $0.contains("gone.bin") }, "\(texts)")
    }

    func testATextFileIsNoCueSheet() throws {
        try write(Data("just some notes\nnothing to see\n".utf8), "notes.cue")
        XCTAssertThrowsError(try list(path("notes.cue")))
    }

    // MARK: - GDI

    func testGdiWithDataAndAudio() throws {
        try write(rawMode1(iso), "track01.bin")
        try write(audio, "track02.raw")
        try write(Data("2\n1 0 4 2352 track01.bin 0\n2 \(iso.count / 2048) 0 2352 \"track02.raw\" 0\n".utf8), "disc.gdi")
        try checkDataAndAudio(path("disc.gdi"))
    }

    // MARK: - CCD/IMG

    func testCloneCdImage() throws {
        let raw = rawMode1(iso)
        try write(raw + audio, "clone.img")
        let sectors = raw.count / 2352
        try write(Data("""
            [CloneCD]
            Version=3
            [Disc]
            TocEntries=5
            Sessions=1
            [Entry 0]
            Session=1
            Point=0xa0
            Control=0x04
            PLBA=-150
            [Entry 1]
            Session=1
            Point=0xa2
            Control=0x00
            PLBA=\(sectors + audio.count / 2352)
            [Entry 2]
            Session=1
            Point=0x01
            Control=0x04
            PLBA=0
            [Entry 3]
            Session=1
            Point=0x02
            Control=0x00
            PLBA=\(sectors)
            """.utf8), "clone.ccd")
        try checkDataAndAudio(path("clone.ccd"))
    }

    // MARK: - binary helpers

    private func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
    private func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian) { Data($0) } }
    private func le64(_ v: Int) -> Data { withUnsafeBytes(of: UInt64(v).littleEndian) { Data($0) } }
    private func be16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).bigEndian) { Data($0) } }
    private func be32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).bigEndian) { Data($0) } }
    private func be64(_ v: Int) -> Data { withUnsafeBytes(of: UInt64(v).bigEndian) { Data($0) } }
    private func zeros(_ n: Int) -> Data { Data(count: n) }

    // MARK: - MDS/MDF

    /// An Alcohol 1.x descriptor: header, one session, two track blocks with extra blocks, and
    /// a footer naming "*.mdf".
    func testMdsWithDataAndAudio() throws {
        let raw = rawMode1(iso)
        try write(raw + audio, "alcohol.mdf")
        let dataSectors = raw.count / 2352, audioSectors = audio.count / 2352
        // offsets: header 0x58, session 0x58 (0x18), tracks 0x70 (2 x 0x50), extras 0x110 (2 x 8),
        // footer 0x120 (0x10), name 0x130
        var mds = Data("MEDIA DESCRIPTOR".utf8) + Data([1, 3]) + le16(0) + le16(1) + zeros(4) + le16(0)
        mds += zeros(8) + le32(0) + zeros(24) + le32(0) + zeros(12) + le32(0x58) + le32(0)
        XCTAssertEqual(mds.count, 0x58)
        mds += le32(-150) + le32(dataSectors + audioSectors) + le16(1) + Data([2, 0]) + le16(1) + le16(2) + le32(0) + le32(0x70)
        func track(mode: UInt8, point: UInt8, extra: Int, start: Int, offset: Int) -> Data {
            var t = Data([mode, 0, 0x14, 0, point, 0, 0, 0, 0, 0, 0, 0]) + le32(extra) + le16(2352)
            t += zeros(18) + le32(start) + le64(offset) + le32(1) + le32(0x120) + zeros(24)
            return t
        }
        mds += track(mode: 0xAA, point: 1, extra: 0x110, start: 0, offset: 0)
        mds += track(mode: 0xA9, point: 2, extra: 0x118, start: dataSectors, offset: raw.count)
        mds += le32(0) + le32(dataSectors) + le32(0) + le32(audioSectors)
        mds += le32(0x130) + le32(0) + le32(0) + le32(0)
        mds += Data("*.mdf".utf8) + Data([0])
        try write(mds, "alcohol.mds")
        try checkDataAndAudio(path("alcohol.mds"))
    }

    // MARK: - NRG

    /// A Nero 2 image: the sectors, then a DAOX chunk for both tracks, SINF, END! and the
    /// "NER5" footer pointing at the chunks.
    func testNrgWithDataAndAudio() throws {
        let raw = rawMode1(iso)
        var nrg = raw + audio
        let chunks = nrg.count
        var dao = be32(0) + zeros(14) + Data([0, 0]) + Data([1, 2])
        func entry(size: Int, mode: UInt8, index1: Int, end: Int) -> Data {
            zeros(12) + be16(size) + Data([mode, 0, 0, 0]) + be64(index1) + be64(index1) + be64(end)
        }
        dao += entry(size: 2352, mode: 0x06, index1: 0, end: raw.count)
        dao += entry(size: 2352, mode: 0x07, index1: raw.count, end: raw.count + audio.count)
        nrg += Data("DAOX".utf8) + be32(dao.count) + dao
        nrg += Data("SINF".utf8) + be32(4) + be32(2)
        nrg += Data("END!".utf8) + be32(0)
        nrg += Data("NER5".utf8) + be64(chunks)
        try write(nrg, "nero.nrg")
        try checkDataAndAudio(path("nero.nrg"))
    }

    /// Nero 1 (DAOI, 32-bit offsets, "NERO" footer) with the ISO as cooked 2048-byte sectors.
    func testNrgVersion1Cooked() throws {
        var nrg = iso
        let chunks = nrg.count
        var dao = be32(0) + zeros(14) + Data([0, 0]) + Data([1, 1])
        dao += zeros(12) + be16(2048) + Data([0, 0, 0, 0]) + be32(0) + be32(0) + be32(iso.count)
        nrg += Data("DAOI".utf8) + be32(dao.count) + dao
        nrg += Data("END!".utf8) + be32(0)
        nrg += Data("NERO".utf8) + be32(chunks)
        try write(nrg, "old.nrg")
        XCTAssertEqual(try list(path("old.nrg")).map(\.name), ["Track01.iso"])
        XCTAssertEqual(data(try extract(path("old.nrg")), "Track01.iso"), iso)
    }

    // MARK: - CDI

    /// A DiscJuggler 3.5 image: both tracks' sectors (data with a 150-sector pregap), then the
    /// descriptor and the version / header-size footer.
    func testCdiWithDataAndAudio() throws {
        let raw = rawMode1(iso)
        let pregap = Data(count: 150 * 2352)
        var cdi = pregap + raw + audio
        let header = cdi.count
        let mark = Data([0, 0, 1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF])
        func track(pregapSectors: Int, sectors: Int, mode: Int) -> Data {
            var t = le32(0) + mark + mark + zeros(4) + Data([4]) + Data("t.wv".utf8)
            t += zeros(11 + 4 + 4) + le32(0) + zeros(2) + le32(pregapSectors) + le32(sectors) + zeros(6)
            t += le32(mode) + zeros(12) + le32(0) + le32(pregapSectors + sectors) + zeros(16) + le32(2)
            t += zeros(29) + zeros(5) + le32(0)
            return t
        }
        var desc = le16(1) + le16(2)
        desc += track(pregapSectors: 150, sectors: raw.count / 2352, mode: 1)
        desc += track(pregapSectors: 0, sectors: audio.count / 2352, mode: 0)
        desc += zeros(4 + 8 + 1)
        cdi += desc
        let total = cdi.count + 8
        cdi += le32(0x8000_0006) + le32(total - header)
        try write(cdi, "juggler.cdi")
        try checkDataAndAudio(path("juggler.cdi"))
    }

    // MARK: - compressed images: encoders for the fixtures

    private func compress(_ data: Data, _ algorithm: compression_algorithm) -> Data {
        let capacity = data.count + 1024
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, algorithm)
            }
        }
        return out.prefix(n)
    }

    /// Raw deflate (Apple's COMPRESSION_ZLIB writes no zlib header).
    private func deflate(_ data: Data) -> Data { compress(data, COMPRESSION_ZLIB) }

    /// A zlib stream: header, raw deflate, Adler-32.
    private func zlib(_ data: Data) -> Data {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        return Data([0x78, 0x9C]) + deflate(data) + be32(Int(b << 16 | a))
    }

    private func bzip2(_ data: Data) throws -> Data {
        let input = path("bz-in-\(UUID().uuidString)")
        try data.write(to: URL(fileURLWithPath: input))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/bzip2")
        p.arguments = ["-k", "-f", input]
        try p.run()
        p.waitUntilExit()
        return try Data(contentsOf: URL(fileURLWithPath: input + ".bz2"))
    }

    private func blocks(_ data: Data, _ size: Int) -> [Data] {
        stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
    }

    /// A compressed image opens straight into the file system it holds (its image is the
    /// archive's main subfile, as for VHD); opened as its own format it is one "<name>.iso",
    /// which extracts to the image byte for byte.
    private func checkSingleISO(_ archive: String, format: String, expected: Data? = nil,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let want = expected ?? iso
        let items = try list(archive)
        XCTAssertTrue(items.contains { $0.name == "hello.txt" }, "\(items.map(\.name))", file: file, line: line)
        let folder = try SZFolder.folder(forPath: archive, formatHint: format, passwordDelegate: nil)
        try folder.loadItems()
        XCTAssertEqual(folder.itemCount, 1, file: file, line: line)
        XCTAssertEqual(folder.sizeOfItem(at: 0), UInt64(want.count), file: file, line: line)
        let dest = path("out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        let o = SZExtractOptions()
        o.outputDirectory = dest
        o.outDirMode = .direct
        o.overwriteMode = .overwrite
        o.formatHint = format
        let result = try XCTUnwrap(SZArchiveExtractor.extractArchives(at: [archive], options: o, progress: nil))
        XCTAssertTrue(result.isOK, "\(result.messages)", file: file, line: line)
        let name = folder.nameOfItem(at: 0)
        XCTAssertEqual(data(dest, name), want, "\(name)", file: file, line: line)
    }

    // MARK: - CSO / ZSO

    /// A PSP CSO v1: 2048-byte blocks, deflated, the first stored (bit 31) as the format allows.
    func testCsoDeflate() throws {
        let parts = blocks(iso, 2048)
        var body = Data(), index: [UInt32] = []
        let start = 0x18 + (parts.count + 1) * 4
        for (i, part) in parts.enumerated() {
            index.append(UInt32(start + body.count) | (i == 0 ? 0x8000_0000 : 0))
            body += i == 0 ? part : deflate(part)
        }
        index.append(UInt32(start + body.count))
        var cso = Data("CISO".utf8) + le32(0x18) + le64(iso.count) + le32(2048) + Data([1, 0]) + le16(0)
        for v in index { cso += le32(Int(v)) }
        try write(cso + body, "game.cso")
        try checkSingleISO(path("game.cso"), format: "CSO")
    }

    /// ZSO: the same layout, LZ4 blocks.
    func testZsoLz4() throws {
        let parts = blocks(iso, 2048)
        var body = Data(), index: [UInt32] = []
        let start = 0x18 + (parts.count + 1) * 4
        for part in parts {
            index.append(UInt32(start + body.count))
            body += compress(part, COMPRESSION_LZ4_RAW)
        }
        index.append(UInt32(start + body.count))
        var zso = Data("ZISO".utf8) + le32(0x18) + le64(iso.count) + le32(2048) + Data([1, 0]) + le16(0)
        for v in index { zso += le32(Int(v)) }
        try write(zso + body, "game.zso")
        try checkSingleISO(path("game.zso"), format: "ZSO")
    }

    /// A Wii compact ISO: 32 KB blocks, an all-zero block left out of the file.
    func testWiiCiso() throws {
        let blockSize = 0x8000
        var image = iso
        image += Data(count: (blockSize - image.count % blockSize) % blockSize)   // whole blocks
        image += Data(count: blockSize)                                           // an empty block
        image += Data(repeating: 0x5A, count: blockSize)                          // and data after it
        var map = Data(count: 0x8000 - 8), body = Data()
        for (i, part) in blocks(image, blockSize).enumerated() {
            if part.allSatisfy({ $0 == 0 }) { continue }
            map[i] = 1
            body += part
        }
        try write(Data("CISO".utf8) + le32(blockSize) + map + body, "wii.ciso")
        try checkSingleISO(path("wii.ciso"), format: "CSO", expected: image)
    }

    // MARK: - ISZ

    /// UltraISO: 64-byte header, an obfuscated table of 3-byte entries (zlib, zero, bzip2,
    /// stored), the blocks.
    func testIszMixedBlocks() throws {
        let blockSize = 0x4000
        var image = iso
        image += Data(count: (2048 - image.count % 2048) % 2048)
        let parts = blocks(image, blockSize)
        var entries: [(UInt32, UInt32)] = [], body = Data()
        for (i, part) in parts.enumerated() {
            if part.allSatisfy({ $0 == 0 }) { entries.append((0, UInt32(part.count))); continue }
            switch i % 3 {
            case 0: let z = zlib(part); entries.append((2, UInt32(z.count))); body += z
            case 1:
                var bz = try bzip2(part)
                bz[0] = 0; bz[1] = 0; bz[2] = 0                   // as UltraISO stores it
                entries.append((3, UInt32(bz.count))); body += bz
            default: entries.append((1, UInt32(part.count))); body += part
            }
        }
        var table = Data()
        for (kind, size) in entries {
            let v = kind << 22 | size
            table += Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF)])
        }
        let key: [UInt8] = [0xB6, 0x8C, 0xA5, 0xDE]
        for i in 0..<table.count { table[i] ^= key[i % 4] }
        let ptrOffset = 64, dataOffset = 64 + table.count
        var h = Data("IsZ!".utf8) + Data([64, 1]) + le32(0) + le16(2048) + le32(image.count / 2048)
        h += Data([0]) + le64(0) + le32(parts.count) + le32(blockSize) + Data([3, 0])
        h += le32(ptrOffset) + le32(0) + le32(dataOffset) + Data([0])
        h += Data(count: 64 - h.count)
        try write(h + table + body, "ultra.isz")
        try checkSingleISO(path("ultra.isz"), format: "ISZ", expected: image)
    }

    // MARK: - zisofs

    func testZisofsFile() throws {
        let blockSize = 1 << 15
        let parts = blocks(iso, blockSize)
        var pointers: [Int] = [], body = Data()
        let start = 16 + (parts.count + 1) * 4
        for part in parts {
            pointers.append(start + body.count)
            body += zlib(part)
        }
        pointers.append(start + body.count)
        var z = Data([0x37, 0xE4, 0x53, 0x96, 0xC9, 0xDB, 0xD6, 0x07]) + le32(iso.count) + Data([4, 15, 0, 0])
        for p in pointers { z += le32(p) }
        try write(z + body, "packed.iso.zisofs")
        try checkSingleISO(path("packed.iso.zisofs"), format: "zisofs")
    }

    // MARK: - ECM

    /// The EDC of a CD sector, bit by bit (independent of the handler's table).
    private func edc(_ d: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in d {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xD801_8001 : crc >> 1 }
        }
        return crc
    }

    /// An ECM record header: type and count - 1, 5 bits then 7 per byte.
    private func ecmHeader(type: Int, count: UInt32) -> Data {
        var n = count &- 1
        var out = Data([UInt8(type) | UInt8((n & 0x1F) << 2)])
        n >>= 5
        while n != 0 {
            out[out.count - 1] |= 0x80
            out.append(UInt8(n & 0x7F))
            n >>= 7
        }
        return out
    }

    /// Mode 1 sectors (address + data stored), 5 Mode 2 Form 1 sectors (subheader + data
    /// stored) and raw audio bytes; the handler rebuilds sync, header and EDC / ECC.
    func testEcmRebuildsTheSectors() throws {
        let raw = rawMode1(iso)
        let mode1 = raw.count / 2352
        var ecm = Data("ECM".utf8) + Data([0])
        ecm += ecmHeader(type: 1, count: UInt32(mode1))
        for i in 0..<mode1 {
            let s = raw.subdata(in: (i * 2352)..<((i + 1) * 2352))
            ecm += s.subdata(in: 12..<15) + s.subdata(in: 16..<2064)
        }
        let form1 = 5
        let sub = Data([0, 0, 0x08, 0])
        ecm += ecmHeader(type: 2, count: UInt32(form1))
        for i in 0..<form1 { ecm += sub + Data(repeating: UInt8(0x40 + i), count: 2048) }
        ecm += ecmHeader(type: 0, count: UInt32(audio.count))
        ecm += audio
        ecm += Data([0xFC, 0xFF, 0xFF, 0xFF, 0x3F]) + le32(0)      // end of records, image EDC
        try write(ecm, "game.bin.ecm")

        let folder = try SZFolder.folder(forPath: path("game.bin.ecm"), formatHint: "ECM", passwordDelegate: nil)
        try folder.loadItems()
        XCTAssertEqual(folder.itemCount, 1)
        XCTAssertEqual(folder.nameOfItem(at: 0), "game.bin")
        let total = mode1 * 2352 + form1 * 2336 + audio.count
        XCTAssertEqual(folder.sizeOfItem(at: 0), UInt64(total))
        let bin = data(try extract(path("game.bin.ecm")), "game.bin")
        XCTAssertEqual(bin.count, total)
        for i in [0, 1, mode1 / 2, mode1 - 1] {
            let s = bin.subdata(in: (i * 2352)..<((i + 1) * 2352))
            XCTAssertEqual(s.prefix(12), Data([0] + [UInt8](repeating: 0xFF, count: 10) + [0]), "sync \(i)")
            XCTAssertEqual(s[15], 1, "mode \(i)")
            XCTAssertEqual(s.subdata(in: 12..<15), raw.subdata(in: (i * 2352 + 12)..<(i * 2352 + 15)), "address \(i)")
            XCTAssertEqual(s.subdata(in: 16..<2064), iso.subdata(in: (i * 2048)..<((i + 1) * 2048)), "data \(i)")
            let stored = s.subdata(in: 0x810..<0x814).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            XCTAssertEqual(UInt32(littleEndian: stored), edc(s.prefix(0x810)), "EDC \(i)")
            XCTAssertFalse(s.subdata(in: 0x81C..<0x930).allSatisfy { $0 == 0 }, "ECC \(i)")
        }
        let f1 = bin.subdata(in: (mode1 * 2352)..<(mode1 * 2352 + 2336))
        XCTAssertEqual(f1.prefix(8), sub + sub, "the subheader, written twice")
        XCTAssertEqual(f1.subdata(in: 8..<2056), Data(repeating: 0x40, count: 2048))
        let f1edc = f1.subdata(in: 0x808..<0x80C).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: f1edc), edc(f1.prefix(0x808)), "Form 1 EDC")
        XCTAssertEqual(bin.suffix(audio.count), audio)
    }

    // MARK: - CHD

    /// A CHD v4 file around `logical`: deflated hunks, the second stored, all-zero hunks as
    /// "mini" entries, and `metadata` (tag, text) entries chained at the end.
    private func chd(_ logical: Data, hunkBytes: Int, metadata: [(String, String)]) -> Data {
        var hunks = blocks(logical, hunkBytes)
        if let last = hunks.last, last.count < hunkBytes { hunks[hunks.count - 1] = last + Data(count: hunkBytes - last.count) }
        let mapStart = 108, dataStart = mapStart + hunks.count * 16
        var map = Data(), body = Data()
        for (i, hunk) in hunks.enumerated() {
            if hunk.allSatisfy({ $0 == 0 }) {
                map += be64(0) + be32(0) + be16(0) + Data([0, 3])
                continue
            }
            let stored = i == 1
            let packed = stored ? hunk : deflate(hunk)
            map += be64(dataStart + body.count) + be32(0) + be16(packed.count & 0xFFFF) + Data([UInt8(packed.count >> 16), stored ? 2 : 1])
            body += packed
        }
        var meta = Data()
        let metaStart = dataStart + body.count
        for (k, entry) in metadata.enumerated() {
            let text = Data(entry.1.utf8) + Data([0])
            let here = metaStart + meta.count
            let next = k + 1 < metadata.count ? here + 16 + text.count : 0
            meta += Data(entry.0.utf8) + be32(text.count) + be64(next) + text
        }
        var h = Data("MComprHD".utf8) + be32(108) + be32(4) + be32(0) + be32(1) + be32(hunks.count)
        h += be64(logical.count) + be64(metadata.isEmpty ? 0 : metaStart) + be32(hunkBytes) + zeros(60)
        XCTAssertEqual(h.count, 108)
        return h + map + body + meta
    }

    /// A CD: frames of 2352 + 96 bytes, each track padded to 4 frames, audio big-endian.
    func testChdCdWithDataAndAudio() throws {
        func frames(_ sectors: Data, swap: Bool) -> (Data, Int) {
            var out = Data()
            let n = sectors.count / 2352
            for f in 0..<n {
                var s = sectors.subdata(in: (f * 2352)..<((f + 1) * 2352))
                if swap { for j in stride(from: 0, to: s.count, by: 2) { s.swapAt(s.startIndex + j, s.startIndex + j + 1) } }
                out += s + Data(count: 96)
            }
            let padded = (n + 3) / 4 * 4
            out += Data(count: (padded - n) * 2448)
            return (out, n)
        }
        let (dataFrames, dataCount) = frames(rawMode1(iso), swap: false)
        let (audioFrames, audioCount) = frames(audio, swap: true)
        let logical = dataFrames + audioFrames
        let file = chd(logical, hunkBytes: 8 * 2448, metadata: [
            ("CHT2", "TRACK:1 TYPE:MODE1_RAW SUBTYPE:NONE FRAMES:\(dataCount) PREGAP:0 PGTYPE:MODE1 PGSUB:RW POSTGAP:0"),
            ("CHT2", "TRACK:2 TYPE:AUDIO SUBTYPE:NONE FRAMES:\(audioCount) PREGAP:0 PGTYPE:AUDIO PGSUB:RW POSTGAP:0"),
        ])
        try write(file, "arcade.chd")
        try checkDataAndAudio(path("arcade.chd"))
    }

    /// A hard disk: no track list, one image.
    func testChdHardDisk() throws {
        let disk = iso + Data(count: 4096)
        try write(chd(disk, hunkBytes: 4096, metadata: []), "disk.chd")
        let items = try list(path("disk.chd"))
        XCTAssertEqual(items.map(\.name), ["image.img"])
        XCTAssertEqual(data(try extract(path("disk.chd")), "image.img"), disk)
    }
}
