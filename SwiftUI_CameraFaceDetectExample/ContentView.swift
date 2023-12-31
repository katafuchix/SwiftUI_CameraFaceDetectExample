//
//  ContentView.swift
//  SwiftUI_CameraFaceDetectExample
//
//  Created by cano on 2023/05/23.
//

import SwiftUI
import AVFoundation
import Vision
import Observation

// 顔認識のための構造体
struct FaceDetection {
    let bounds: CGRect
    let landmarks: [VNFaceLandmarkRegion2D]
}

struct ContentView: View {
    var body: some View {
        CameraView()
    }
}

struct CameraView: View {
    private var cameraViewModel = CameraViewModel()
    
    var body: some View {
        ZStack {
            if let previewImage = cameraViewModel.previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    //.aspectRatio(contentMode: .fit)
                    //.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            cameraViewModel.startCaptureSession()
        }
        .onDisappear {
            cameraViewModel.stopCaptureSession()
        }
    }
}

@Observable
class CameraViewModel: NSObject {
    private let session = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    
    var previewImage: UIImage?
    
    private let faceDetectionRequest = VNDetectFaceLandmarksRequest()

    override init() {
        super.init()
        setupCameraInput()
        setupVideoOutput()
    }
    
    func startCaptureSession() {
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    func stopCaptureSession() {
        session.stopRunning()
    }
    
    private func setupCameraInput() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }
        //session.sessionPreset = .photo
        if session.canAddInput(input) {
            session.addInput(input)
        }
    }
    
    private func setupVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        //videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cameraQueue"))
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        }
    }
    
    // 顔認識処理を行うメソッド
    private func performFaceDetection(on image: CIImage) -> [VNFaceObservation] {
        let faceDetectionHandler = VNImageRequestHandler(ciImage: image, options: [:])
        try? faceDetectionHandler.perform([faceDetectionRequest])
        
        return faceDetectionRequest.results ?? []
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //connection.videoOrientation = .portrait
        // サンプルバッファから画像データを取得
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let correctedImage = ciImage.oriented(.right) // 回転と方向の補正
        
        let context = CIContext()
        // CIImageをCGImageに変換する
        guard let cgImage = context.createCGImage(correctedImage, from: correctedImage.extent) else {
            return
        }
        // CGImageからUIImageを作成
        let uiImage = UIImage(cgImage: cgImage)
        
        // 顔認識処理を実行
        let faceDetections = performFaceDetection(on: correctedImage)
        // 顔を矩形で認識
        guard let image = self.drawFaceRectangles(on: uiImage, with: faceDetections) else { return }
        
        // 画像の更新をメインスレッドで行う
        DispatchQueue.main.async { [weak self] in
            // ViewModelのプロパティに画像を設定
            self?.previewImage = image
        }
    }
    
    // 顔認証描画処理 できればCombineで行いたい
    func drawFaceRectangles(on image: UIImage, with observations: [VNFaceObservation]) -> UIImage? {
        if observations.count == 0 {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, true, 0.0)
        image.draw(at: CGPoint.zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // 座標系の変換
        context.translateBy(x: 0, y: image.size.height)
        context.scaleBy(x: 1, y: -1)

        let imageSize = image.size

        for observation in observations {
            let boundingBox = observation.boundingBox

            // 矩形の描画
            let rect = CGRect(x: boundingBox.origin.x * imageSize.width,
                              y: boundingBox.origin.y * imageSize.height,
                              width: boundingBox.size.width * imageSize.width,
                              height: boundingBox.size.height * imageSize.height)
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(2.0)
            context.addRect(rect)
            context.drawPath(using: .stroke)
        }

        let drawnImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return drawnImage
    }

}
