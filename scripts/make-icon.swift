// Иконка приложения из App/Bundle/AppIcon.svg (адаптивная иконка Android-клиента,
// scripts/android-icon-to-svg.py). Запуск: swift scripts/make-icon.swift App/Bundle/AppIcon.svg App/Bundle/AppIcon.icns
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let svg = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-icon.swift <in.svg> <out.icns>"); exit(2)
}
let iconset = NSTemporaryDirectory() + "FreeTurn.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let size = CGFloat(pixels)
    // Сетка иконок macOS: скруглённый квадрат 824/1024 по центру.
    let side = size * 824 / 1024
    let rect = NSRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side)
    NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237).addClip()
    // Android показывает только центр слоя (маска ~2/3), поэтому центр и увеличиваем.
    let zoom: CGFloat = 1.3
    svg.draw(in: rect.insetBy(dx: -side * (zoom - 1) / 2, dy: -side * (zoom - 1) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    try render(points * scale).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", args[2]]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
