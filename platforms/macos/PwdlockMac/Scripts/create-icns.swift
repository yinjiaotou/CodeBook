import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let chunkTypes = ["icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10"]

guard arguments.count == chunkTypes.count + 1 else {
    fputs(
        "Usage: create-icns.swift OUTPUT.icns 16.png 32.png 64.png 128.png 256.png 512.png 1024.png\\n",
        stderr
    )
    exit(2)
}

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndianValue = value.bigEndian
    return withUnsafeBytes(of: &bigEndianValue) { Data($0) }
}

func chunkTypeData(_ type: String) -> Data {
    Data(type.utf8)
}

var chunkData = Data()
for (type, path) in zip(chunkTypes, arguments.dropFirst()) {
    let pngData: Data
    do {
        pngData = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        fputs("Unable to read PNG for \(type): \(path)\\n", stderr)
        exit(1)
    }

    guard pngData.count <= Int(UInt32.max) - 8 else {
        fputs("PNG is too large for ICNS chunk \(type): \(path)\\n", stderr)
        exit(1)
    }

    chunkData.append(chunkTypeData(type))
    chunkData.append(bigEndianData(UInt32(pngData.count + 8)))
    chunkData.append(pngData)
}

guard chunkData.count <= Int(UInt32.max) - 8 else {
    fputs("ICNS file is too large.\\n", stderr)
    exit(1)
}

var output = Data("icns".utf8)
output.append(bigEndianData(UInt32(chunkData.count + 8)))
output.append(chunkData)

do {
    try output.write(to: URL(fileURLWithPath: arguments[0]), options: .atomic)
} catch {
    fputs("Unable to write ICNS file: \(arguments[0])\\n", stderr)
    exit(1)
}
