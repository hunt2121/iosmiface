// SPDX-License-Identifier: MIT
import XCTest
@testable import FaceCompiler

final class FaceCompilerTests: XCTestCase {
    func testToIntLikeTinyXML() {
        XCTAssertEqual(toInt(Array(" 12px".utf8)), 12)
        XCTAssertEqual(toInt(Array("-7".utf8)), -7)
        XCTAssertEqual(toInt(Array("0x1F".utf8)), 31)
        XCTAssertNil(toInt(Array("abc".utf8)))
        XCTAssertEqual(toBool(Array("True".utf8)), true)
        XCTAssertEqual(toBool(Array("2".utf8)), true)
    }

    func testRLERoundtrip() {
        var raw: [UInt8] = []
        for i in 0..<5000 { raw.append(UInt8((i / 37) % 7)); raw.append(UInt8(i % 3)); raw.append(9) }
        let block = RLE.block(raw, elem: 3)
        let back = RLE.decompress(block, from: 8, outSize: raw.count, elem: 3)
        XCTAssertEqual(back, raw)
    }

    func testPNGRoundtrip() {
        let w = 37, h = 23
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<px.count { px[i] = UInt8((i * 7 + i / 13) & 0xFF) }
        let png = PNG.encode(w, h, px)
        let img = PNG.decode(png)
        XCTAssertEqual(img?.w, w); XCTAssertEqual(img?.h, h); XCTAssertEqual(img?.rgba, px)
    }

    /// Новий циферблат із нуля -> .bin -> розпакування -> знову .bin: результат однаковий.
    func testBuildUnpackBuild() throws {
        let w = 20, h = 10
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: px.count, by: 4) { px[i] = 200; px[i + 1] = UInt8(i % 256); px[i + 2] = 40; px[i + 3] = 255 }
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Watchface id="123456789" name="Test">
            <Resources>
                <Image name="bg" src="bg.png" compressMethod="RLEReversed" format="indexed8" recolorEnable="false"/>
                <ImageArray name="digits" compressMethod="RLEReversed" format="RGB565A8" recolorEnable="false">
                    <Image src="d/0.png"/>
                    <Image src="d/1.png"/>
                </ImageArray>
                <DataItemImageNumber name="hour" source="timeHour" ref="@digits" totalDigits="2" decimalDigits="0" align="left" leadingZero="true" trailingZero="false" renderRule="alwaysShow" rotation="0" decimalOffsetX="0" space="1"/>
                <DataItemText name="t" color="#FF8800" opacity="80" fontId="misans" fontWeight="bold" letterSpace="1" align="center" longMode="clip" style="normal" lineSpace="2" w="100" h="30" rotation="0" string="Hi %s">
                    <Content source="timeHour"/>
                </DataItemText>
            </Resources>
            <Theme type="normal" name="main" bgColor="#000000">
                <Layout ref="@bg" x="0" y="0"/>
                <Layout ref="@hour" x="10" y="20"/>
                <Layout ref="@t" x="0" y="50"/>
            </Theme>
        </Watchface>
        """
        let png = Data(PNG.encode(w, h, px))
        let st = MemoryStorage(["manifest.xml": Data(manifest.utf8), "bg.png": png, "d/0.png": png, "d/1.png": png])
        let bin = try WatchfaceCompiler.build(from: st)
        let out = MemoryStorage()
        try WatchfaceCompiler.unpack(bin, to: out)
        XCTAssertNotNil(out.files["manifest.xml"])
        let bin2 = try WatchfaceCompiler.build(from: out)
        XCTAssertEqual(bin, bin2)
    }
}
