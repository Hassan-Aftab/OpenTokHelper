 //
 //  OpenTokUtil.swift
 //  iMedDoctor
 //
 //  Created by Hassan Aftab on 07/04/2018.
 //  Copyright © 2018 Mac. All rights reserved.
 //
 
 import UIKit
 import OpenTok
 import SwiftyJSON
 
 struct SignalTypes {
    static let SIGNAL_TYPE_CHAT = "msg";
    static let SIGNAL_TYPE_CALL = "begincall";
    static let SIGNAL_TYPE_CALL_REJECTED = "call_rejected";
    static let SIGNAL_TYPE_CALL_ACCEPTED = "acceptcall";
    static let SIGNAL_TYPE_CALL_Cacel = "cancelcall";
    static let CALL_ACCEPTED_yes = "yes";
    static let CALL_ACCEPTED_no = "no";
    static let CALL_END = "endcall";
 }
 
 @objc
 protocol OpenTokUtilDelegate {
    @objc optional func openTokUtil(_ openTokUtil: OpenTokUtil, didRecieve message: String)
    @objc optional func openTokUtil(_ openTokUtil: OpenTokUtil, call view: UIView)
    @objc optional func openTokUtilCallIncoming(_ openTokUtil: OpenTokUtil, info: [String:Any])
    @objc optional func openTokUtilCallDidDisconnect(_ openTokUtil: OpenTokUtil)
    @objc optional func openTokUtilCallDidConnect(_ openTokUtil: OpenTokUtil)
    
 }
 
 class OpenTokUtil: NSObject {
    
    static var shared = OpenTokUtil()
    
    var delegate : OpenTokUtilDelegate?
    
    var publisher: OTPublisher?
    
    var subscriber: OTSubscriber?
    
    let captureSession = AVCaptureSession()
    
    
    
    // Replace with your OpenTok API key
    var kApiKey = "" 
    // Replace with your generated session ID
    var kSessionId = ""
    // Replace with your generated token
    var kToken = ""
    
    let captureQueue = DispatchQueue(label: "com.tokbox.VideoCapture", attributes: [])
    lazy var session: OTSession = {
        return OTSession(apiKey: kApiKey, sessionId: kSessionId, delegate: self)!
    }()
    
    var stream : OTStream?
    
    
    override init() {
        super.init()
        doConnect()
        
    }
    
    fileprivate func doConnect() {
        var error: OTError?
        
        session.connect(withToken: kToken, error: &error)
    }
    
    func endCall(_ info: [String:AnyObject]) {
        var error: OTError?
        defer {
            print(error?.localizedDescription)
        }
        if publisher != nil {
            session.unpublish(publisher!, error: &error)
            publisher?.view?.removeFromSuperview()
        }
        if subscriber != nil {
            session.unsubscribe(subscriber!, error: &error)
            subscriber!.view?.removeFromSuperview()
        }
        
        
        session.signal(withType: SignalTypes.CALL_END, string: dictToJSON(dictionary: info), connection: nil, error: &error)
        
        print(error?.localizedDescription ?? "")
        
    }
    
    fileprivate func connectCall()->UIView? {
        var error: OTError?
        
        session.publish(publisher!, error: &error)
        
        if let pubView = publisher?.view {
            return pubView
        }
        return nil
    }
    
    func doSubscribe(_ stream: OTStream) {
        var error: OTError?
        defer {
            processError(error)
        }
        
        
        subscriber = OTSubscriber(stream: stream, delegate: self)
        
        session.subscribe(subscriber!, error: &error)
    }
    
    fileprivate func processError(_ error: OTError?) {
        if let err = error {
            print(err.localizedDescription)
        }
    }
    
    fileprivate func cleanupSubscriber() {
        subscriber?.view?.removeFromSuperview()
        subscriber = nil
    }
    
    
    
    func sendMessage(_ info: [String: AnyObject]) -> Bool {
        var error: OTError?
        
        session.signal(withType: SignalTypes.SIGNAL_TYPE_CHAT, string: dictToJSON(dictionary: info), connection: nil, error: &error)
        
        print(error?.localizedDescription ?? "")
        
        return error == nil
    }
    
    func call(_ info:[String:AnyObject]) {
        var error: OTError?
        session.signal(withType: SignalTypes.SIGNAL_TYPE_CALL, string: dictToJSON(dictionary: info), connection: nil, error: &error)
        print(error?.localizedDescription ?? "")
        _ = doPublish()
    }
    
    func callAccepted(_ dict: [String: AnyObject]) {
        var error: OTError?
        
        session.signal(withType: SignalTypes.SIGNAL_TYPE_CALL_ACCEPTED, string: dictToJSON(dictionary: dict), connection: nil, error: &error)
        print(error?.localizedDescription ?? "")
    }
    
    func callRejected(_ dict: [String: AnyObject]) {
        var error: OTError?
        
        session.signal(withType: SignalTypes.SIGNAL_TYPE_CALL_REJECTED, string: dictToJSON(dictionary: dict), connection: nil, error: &error)
        print(error?.localizedDescription ?? "")
        
    }
    func doPublish()->UIView? {
        var error: OTError? = nil
        defer {
            processError(error)
        }
        let settings = OTPublisherSettings()
        settings.name = UIDevice.current.name
        print(UIDevice.current.name)
        
        publisher = OTPublisher(delegate: self, settings: settings)
        publisher?.videoCapture = TBExampleVideoCapture()
        
        let videoRender = TBExampleVideoRender(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        publisher?.videoRender = videoRender
        session.publish(publisher!, error: &error)
        
        
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if let vc = appDelegate.window?.rootViewController?.presentedViewController as? CallVC {
            videoRender.frame = vc.camView.bounds
            vc.camView.addSubview(videoRender)
        }
        
        
        return videoRender 
        
    }
 }
 
 extension OpenTokUtil: OTSessionDelegate {
    func sessionDidConnect(_ session: OTSession) {
        print("The client connected to the OpenTok session.")
    }
    
    func session(_ session: OTSession, receivedSignalType type: String?, from connection: OTConnection?, with string: String?) {
        print(string ?? "")
        let json = JSON(parseJSON: string ?? "")
        if type == SignalTypes.SIGNAL_TYPE_CHAT {
            var fromSelf = false
            if connection?.connectionId == session.connection?.connectionId {
                fromSelf = true
            }
            if !fromSelf {
                
                if json["recieverLoginId"].stringValue == UserUtil.getLoginId() {
                    delegate?.openTokUtil?(self, didRecieve: (json["msg"].stringValue ))
                }
                
            }
        }
        else if type == SignalTypes.SIGNAL_TYPE_CALL {
            
            if connection?.connectionId != session.connection?.connectionId && json["recieverLoginId"].stringValue == UserUtil.getLoginId() {
                delegate?.openTokUtilCallIncoming?(self, info: json.rawValue as! [String : Any])
            }
        }
        else if type == SignalTypes.SIGNAL_TYPE_CALL_REJECTED || type == SignalTypes.SIGNAL_TYPE_CALL_Cacel {
            endCall()
            delegate?.openTokUtilCallDidDisconnect?(self)
        }
    }
    func sessionDidDisconnect(_ session: OTSession) {
        print("The client disconnected from the OpenTok session.")
        doConnect()
    }
    
    func session(_ session: OTSession, didFailWithError error: OTError) {
        print("The client failed to connect to the OpenTok session: \(error).")
    }
    func session(_ session: OTSession, streamCreated stream: OTStream) {
        print("A stream was created in the session.") // Call Incoming
        
        //        if session.connection?.connectionId != self.session.connection?.connectionId {
        self.stream = stream
        //        }
        delegate?.openTokUtilCallDidConnect?(self)
    }
    
    
    
    func session(_ session: OTSession, streamDestroyed stream: OTStream) {
        print("A stream was destroyed in the session.")
        if let subStream = subscriber?.stream, subStream.streamId == stream.streamId {
            cleanupSubscriber()
            endCall()
            delegate?.openTokUtilCallDidDisconnect?(self)
        }
        
    }
    
 }
 
 extension OpenTokUtil: OTPublisherDelegate {
    func publisher(_ publisher: OTPublisherKit, didFailWithError error: OTError) {
        print("The publisher failed: \(error)")
    }
    func publisher(_ publisher: OTPublisherKit, streamDestroyed stream: OTStream) {
        if let subStream = subscriber?.stream, subStream.streamId == stream.streamId {
            cleanupSubscriber()
        }
    }
    func publisher(_ publisher: OTPublisherKit, streamCreated stream: OTStream) {
        
    }
    
 }
 
 extension OpenTokUtil: OTSubscriberDelegate {
    public func subscriberDidConnect(toStream subscriber: OTSubscriberKit) {
        print("The subscriber did connect to the stream.\( User.currentUser?.id)")
        if let subsView = self.subscriber?.view {
            delegate?.openTokUtil?(self, call: subsView)
        }
    }
    func subscriberDidDisconnect(fromStream subscriber: OTSubscriberKit) {
        delegate?.openTokUtilCallDidDisconnect?(self)
    }
    
    public func subscriber(_ subscriber: OTSubscriberKit, didFailWithError error: OTError) {
        print("The subscriber failed to connect to the stream.")
    }
 }
 
 extension OpenTokUtil {
    func dictToJSON(dictionary: [String: AnyObject]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted)
            return String(bytes: data, encoding: String.Encoding.utf8)!
        }
        catch _ as NSError {
            return ""
        }
    }
 }
