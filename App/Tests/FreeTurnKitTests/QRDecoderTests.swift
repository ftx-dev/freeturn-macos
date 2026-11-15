import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import FreeTurnKit

private func qrImage(_ text: String) -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    return CIContext().createCGImage(scaled, from: scaled.extent)!
}

@Test func decodesGeneratedQR() {
    #expect(QRDecoder.decode(qrImage(goldenMinimal)) == [goldenMinimal])
}

@Test func noQRReturnsEmpty() {
    let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    #expect(QRDecoder.decode(CIContext().createCGImage(blank, from: blank.extent)!).isEmpty)
}
