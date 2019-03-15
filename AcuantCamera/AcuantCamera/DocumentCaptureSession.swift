//
//  CaptureSession.swift

//
//  Created by Tapas Behera on 7/9/18.
//  Copyright © 2018 com.acuant. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import AcuantCommon
import AcuantImagePreparation

public class DocumentCaptureSession :AVCaptureSession,AVCaptureMetadataOutputObjectsDelegate,AVCaptureVideoDataOutputSampleBufferDelegate,AVCapturePhotoCaptureDelegate{
    private let context = CIContext()
    var frame : UIImage? = nil
    var croppedFrame : Image? = nil
    var stringValue : String? = nil
    var delegate : DocumentCaptureDelegate? = nil
    var captureDevice: AVCaptureDevice?
    private var captured = false
    private var cropping = false
    private var input : AVCaptureDeviceInput? = nil
    private var videoOutput : AVCaptureVideoDataOutput? = nil
    private var captureMetadataOutput : AVCaptureMetadataOutput? = nil
    let stillImageOutput = AVCapturePhotoOutput()
    
    
    public class func getDocumentCaptureSession(delegate:DocumentCaptureDelegate?,captureDevice:AVCaptureDevice?)->DocumentCaptureSession{
        return DocumentCaptureSession().getDocumentCaptureSession(delegate: delegate!, captureDevice: captureDevice)
    }
    
    private func getDocumentCaptureSession(delegate:DocumentCaptureDelegate?,captureDevice: AVCaptureDevice?)->DocumentCaptureSession{
        self.delegate = delegate
        self.captureDevice = captureDevice
        return self;
    }
    
    
    
    override public func startRunning() {
        DispatchQueue.main.async {
            super.startRunning()
            DispatchQueue(label: "come.acuant.avcapture.queue.0",qos:.userInteractive,attributes:.concurrent).async {
                self.automaticallyConfiguresApplicationAudioSession = false
                self.usesApplicationAudioSession = false
                if(self.captureDevice?.isFocusModeSupported(.continuousAutoFocus))! {
                    try! self.captureDevice?.lockForConfiguration()
                    self.captureDevice?.focusMode = .continuousAutoFocus
                    self.captureDevice?.unlockForConfiguration()
                }
                do {
                    self.input = try AVCaptureDeviceInput(device: self.captureDevice!)
                    if(self.canAddInput(self.input!)){
                        self.addInput(self.input!)
                    }
                } catch _ as NSError {
                    return
                }
                
                if(self.canSetSessionPreset(AVCaptureSession.Preset.hd4K3840x2160)){
                    self.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
                }else if(self.canSetSessionPreset(AVCaptureSession.Preset.photo)){
                    self.sessionPreset = AVCaptureSession.Preset.photo
                }else if(self.canSetSessionPreset(AVCaptureSession.Preset.high)){
                    self.sessionPreset = AVCaptureSession.Preset.high
                }
                
                //self.sessionPreset = AVCaptureSession.Preset.high
                
                
                self.videoOutput = AVCaptureVideoDataOutput()
                self.videoOutput?.alwaysDiscardsLateVideoFrames = true
                let frameQueue = DispatchQueue(label: "com.acuant.frame.queue",qos:.userInteractive,attributes:.concurrent)
                self.videoOutput?.setSampleBufferDelegate(self, queue: frameQueue)
                if(self.canAddOutput(self.videoOutput!)){
                    self.addOutput(self.videoOutput!)
                }
                
                if(self.canAddOutput(self.stillImageOutput)){
                    self.addOutput(self.stillImageOutput)
                }
                
                /* Check for metadata */
                self.captureMetadataOutput = AVCaptureMetadataOutput()
                let metadataQueue = DispatchQueue(label: "com.acuant.metadata.queue",qos:.userInteractive,attributes:.concurrent)
                self.captureMetadataOutput?.setMetadataObjectsDelegate(self, queue: metadataQueue)
                if (self.canAddOutput(self.captureMetadataOutput!)) {
                    self.addOutput(self.captureMetadataOutput!)
                    self.captureMetadataOutput?.metadataObjectTypes = [.pdf417]
                }
                DispatchQueue.main.async {
                    self.delegate?.didStartCaptureSession()
                }
            }
        }
    }
    
    
    // MARK: Sample buffer to UIImage conversion
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let frameQueue = DispatchQueue(label: "com.acuant.image.queue",attributes:.concurrent)
        frameQueue.async {
            self.frame = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer)
            if(self.frame != nil && self.captured == false){
                if(self.cropping == true){
                    return
                }
                self.cropping = true
                self.croppedFrame = self.cropImage(image: self.frame!)
                let croppedUIImage : UIImage? = self.croppedFrame?.image
                self.cropping = false
                let dpiThreshold = CaptureConstants.RESOLUTION_THRESHOLD
                if((self.croppedFrame?.error == nil || (self.croppedFrame?.dpi)! >= dpiThreshold) && croppedUIImage != nil && self.croppedFrame?.isCorrectAspectRatio == true && self.captured == false){
                    DispatchQueue.main.async{
                        self.delegate?.readyToCapture()
                    }
                    self.captured = true
                    self.capturePhoto()
                }else{
                    let croppedImage = Image()
                    croppedImage.error = self.croppedFrame?.error
                    DispatchQueue.main.async{
                        if((self.croppedFrame?.dpi)!>CaptureConstants.SMALL_DOCUMENT_DPI_THRESHOLD){
                            croppedImage.documentDetected = true
                        }
                        self.delegate?.documentCaptured(image: croppedImage,barcodeString:self.stringValue)
                    }
                }
            }
            
        }
    }
    
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            if(readableObject.stringValue == nil){
                return
            }
            self.stringValue = readableObject.stringValue
        }
    }
    
    func found2DBarcode(code: String,image:Image!) {
        if(self.captured == false){
            self.capturePhoto()
        }
    }
    
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Check if there is any error in capturing
        guard error == nil else {
            print("Fail to capture photo: \(String(describing: error))")
            return
        }
        
        // Check if the pixel buffer could be converted to image data
        guard let imageData = photo.fileDataRepresentation() else {
            print("Fail to convert pixel buffer")
            return
        }
        
        // Check if UIImage could be initialized with image data
        guard let capturedImage = UIImage.init(data: imageData , scale: 1.0) else {
            print("Fail to convert image data to UIImage")
            return
        }
        
        let croppedFrame = cropImage(image: capturedImage)
        if(croppedFrame!.image != nil){
            let sharpness = AcuantImagePreparation.sharpness(image:croppedFrame!.image!)
            let glare = AcuantImagePreparation.glare(image:croppedFrame!.image!)
            croppedFrame?.hasImageMetrics=true

            croppedFrame?.isBlurry = (sharpness < CaptureConstants.SHARPNESS_THRESHOLD)
            croppedFrame?.sharpnessGrade=sharpness
            croppedFrame?.hasGlare = ( glare < CaptureConstants.GLARE_THRESHOLD );
            croppedFrame?.glareGrade=glare
            
            DispatchQueue.main.async{
                self.captureDevice = nil
                self.stopRunning()
                self.delegate?.documentCaptured(image: croppedFrame,barcodeString:self.stringValue)
                self.delegate = nil
                self.frame = nil
            }
        }else{
            DispatchQueue.main.async{
                self.captureDevice = nil
                self.stopRunning()
                self.delegate?.documentCapturedWithError()
                self.delegate = nil
                self.frame = nil
            }
        }
    }
    
    
    func capturePhoto() {
        let photoSetting = AVCapturePhotoSettings.init(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoSetting.isAutoStillImageStabilizationEnabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.stillImageOutput.capturePhoto(with: photoSetting, delegate: self)
        }
    }
    
    func cropImage(image:UIImage)->Image?{
        let croppingData  = CroppingData()
        croppingData.image = image
    
        let croppingOptions = CroppingOptions()
        croppingOptions.isHealthCard = false
        
        let croppedImage = AcuantImagePreparation.crop(options: croppingOptions, data: croppingData)
        return croppedImage
    }
    
}
