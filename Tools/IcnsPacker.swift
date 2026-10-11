import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: IcnsPacker <iconset directory> <output.icns>\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let chunks: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func fourCC(_ value: String) -> Data {
    Data(value.utf8.prefix(4))
}

func bigEndianData(_ value: UInt32) -> Data {
    var number = value.bigEndian
    return Data(bytes: &number, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for (type, filename) in chunks {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    body.append(fourCC(type))
    body.append(bigEndianData(UInt32(png.count + 8)))
    body.append(png)
}

var icns = Data()
icns.append(fourCC("icns"))
icns.append(bigEndianData(UInt32(body.count + 8)))
icns.append(body)
try icns.write(to: output, options: .atomic)

