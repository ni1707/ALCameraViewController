//
//  SingleImageSavingInteractor.swift
//  ALCameraViewController
//
//  Created by Alex Littlejohn on 2016/02/16.
//  Copyright © 2016 zero. All rights reserved.
//

import UIKit
import Photos
import CoreLocation
import MobileCoreServices

public typealias SingleImageSaverSuccess = (PHAsset) -> Void
public typealias SingleImageSaverFailure = (NSError) -> Void

public class SingleImageSaver {
    private let errorDomain = "com.zero.singleImageSaver"
    
    private var success: SingleImageSaverSuccess?
    private var failure: SingleImageSaverFailure?
    
    private var image: UIImage?
    private var imageData: Data?
    public var locationManager: CLLocation?
    public var lasestHeading: CLLocationDirection?
    
    public init() { }
    
    public func onSuccess(_ success: @escaping SingleImageSaverSuccess) -> Self {
        self.success = success
        return self
    }
    
    public func onFailure(_ failure: @escaping SingleImageSaverFailure) -> Self {
        self.failure = failure
        return self
    }
    
    public func setImage(_ image: UIImage) -> Self {
        self.image = image
        return self
    }
    
    public func setImageData(_ imageData: Data) -> Self {
        self.imageData = imageData
        return self
    }
    
    /// Property to enable or disable location services. Location services in camera is used for EXIF data. Default is false
    public func shouldUseLocation(locationManager: CLLocation?) -> Self {
        self.locationManager = locationManager
        return self
    }
    public func shouldUseHeading(headingManager: CLLocationDirection?) -> Self {
        self.lasestHeading = headingManager
        return self
    }
    
    public func save() -> Self {
        
        _ = PhotoLibraryAuthorizer { error in
            if error == nil {
                self._save()
            } else {
                self.failure?(error!)
            }
        }

        return self
    }
    
    private func _save() {
        guard let image = image, let imageData = imageData else {
            self.invokeFailure()
            return
        }
        
        var assetIdentifier: PHObjectPlaceholder?
        //let location = self.locationManager
        //let date = Date()
        
        let filePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("image\(Int(Date().timeIntervalSince1970)).jpg")
        
        let newImageData = _imageDataWithEXIF(forImage: image, imageData) as Data
        do {
            try newImageData.write(to: filePath)
        } catch {
            return
        }
        
        PHPhotoLibrary.shared()
            .performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: filePath)
                request!.creationDate = Date()
                request!.location = self.locationManager
                assetIdentifier = request?.placeholderForCreatedAsset
            }) { finished, error in
                
                guard let assetIdentifier = assetIdentifier, finished else {
                    self.invokeFailure()
                    return
                }
                
                self.fetch(assetIdentifier)
        }
    }
    
    private func fetch(_ assetIdentifier: PHObjectPlaceholder) {
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier.localIdentifier], options: nil)
        
        DispatchQueue.main.async {
            guard let asset = assets.firstObject else {
                self.invokeFailure()
                return
            }
            
            self.success?(asset)
        }
    }
    
    private func invokeFailure() {
        let error = errorWithKey("error.cant-fetch-photo", domain: errorDomain)
        failure?(error)
    }
    
   
    fileprivate func _imageDataWithEXIF(forImage image: UIImage, _ imageData: Data) -> CFMutableData {
        
        // get EXIF info
        let cgImage = image.cgImage
        let newImageData:CFMutableData = CFDataCreateMutable(nil, 0)
        let type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, "image/jpg" as CFString, kUTTypeImage)
        let destination:CGImageDestination = CGImageDestinationCreateWithData(newImageData, (type?.takeRetainedValue())!, 1, nil)!
        
        // NSMutableDictionary into image
        let imageCopy: Data = UIImageJPEGRepresentation(image, 1)!
        let imageCopySourceRef = CGImageSourceCreateWithData(imageCopy as CFData, nil)
        let imageCopyProperties = CGImageSourceCopyPropertiesAtIndex(imageCopySourceRef!, 0, nil)! as NSDictionary
        let imageMutable: NSMutableDictionary = imageCopyProperties.mutableCopy() as! NSMutableDictionary
        
        // get NSMutableDictionary imageData
        let imageSourceRef = CGImageSourceCreateWithData(imageData as CFData, nil)
        let currentProperties = CGImageSourceCopyPropertiesAtIndex(imageSourceRef!, 0, nil)
        let mutableDict = NSMutableDictionary(dictionary: currentProperties!)
        
        // imageMutable copyto mutableDict
        // kCGImagePropertyTIFFDictionary, kCGImagePropertyGIFDictionary
        let EXIFDictionary: NSMutableDictionary = (mutableDict[kCGImagePropertyExifDictionary as String] as? NSMutableDictionary)!
        // edit sting
        //TIFFDictionary[kCGImagePropertyExifUserComment as String] = "comment"
        imageMutable[kCGImagePropertyExifDictionary as String] = EXIFDictionary
        
        // set GPS
        if let location = self.locationManager {
            imageMutable.setValue(_gpsMetadata(withLocation: location), forKey: kCGImagePropertyGPSDictionary as String)
        }
        
        CGImageDestinationAddImage(destination, cgImage!, imageMutable as CFDictionary)
        CGImageDestinationFinalize(destination)
        
        return newImageData
    }
    
    fileprivate func _gpsMetadata(withLocation location: CLLocation) -> NSMutableDictionary {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        
        f.dateFormat = "yyyy:MM:dd"
        let isoDate = f.string(from: location.timestamp)
        
        f.dateFormat = "HH:mm:ss.SSSSSS"
        let isoTime = f.string(from: location.timestamp)
        
        let GPSMetadata = NSMutableDictionary()
        let altitudeRef = Int(location.altitude < 0.0 ? 1 : 0)
        let latitudeRef = location.coordinate.latitude < 0.0 ? "S" : "N"
        let longitudeRef = location.coordinate.longitude < 0.0 ? "W" : "E"
        
        // GPS metadata
        GPSMetadata[(kCGImagePropertyGPSLatitude as String)] = abs(location.coordinate.latitude)
        GPSMetadata[(kCGImagePropertyGPSLongitude as String)] = abs(location.coordinate.longitude)
        GPSMetadata[(kCGImagePropertyGPSLatitudeRef as String)] = latitudeRef
        GPSMetadata[(kCGImagePropertyGPSLongitudeRef as String)] = longitudeRef
        GPSMetadata[(kCGImagePropertyGPSAltitude as String)] = Int(abs(location.altitude))
        GPSMetadata[(kCGImagePropertyGPSAltitudeRef as String)] = altitudeRef
        GPSMetadata[(kCGImagePropertyGPSTimeStamp as String)] = isoTime
        GPSMetadata[(kCGImagePropertyGPSDateStamp as String)] = isoDate
        
        GPSMetadata[(kCGImagePropertyGPSImgDirectionRef as String)] = "T"
        GPSMetadata[(kCGImagePropertyGPSImgDirection as String)] = lasestHeading
        
        return GPSMetadata
    }
}
