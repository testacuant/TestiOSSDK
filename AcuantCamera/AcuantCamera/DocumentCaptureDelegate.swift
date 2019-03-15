//
//  DocumentCaptureDelegate.swift

//
//  Created by Tapas Behera on 7/9/18.
//  Copyright © 2018 com.acuant. All rights reserved.
//
import AcuantCommon
public protocol DocumentCaptureDelegate {
    func readyToCapture()
    func documentCaptured(image:Image?,barcodeString:String?)
    func documentCapturedWithError()
    func didStartCaptureSession()
}
