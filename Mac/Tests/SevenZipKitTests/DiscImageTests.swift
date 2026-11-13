// DiscImageTests.swift -- the disc-image formats after Iso7z (Mac/Core/Handlers): each test
// builds an image around a real ISO 9660 file system (made with hdiutil) and an audio track,
// opens it as 7-Zip does, and checks the tracks it shows and the bytes they extract to.

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
}
