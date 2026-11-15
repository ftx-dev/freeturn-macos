import CoreGraphics
import Vision

public enum QRDecoder {
    /// Тексты всех QR-кодов на картинке; пусто, если кодов нет.
    public static func decode(_ image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
