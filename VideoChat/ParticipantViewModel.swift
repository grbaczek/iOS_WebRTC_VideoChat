//
//  ParticipantViewModel.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 28/11/2022.
//

import Foundation
import UIKit

@MainActor
class ParticipantViewModel: ObservableObject {
    
    private let webRTCManager = WebRTCManager()
    let currentPeer: WebRTCManager.peer
    let chatRoomId: String
    
    init(chatRoomId: String, currentPeer: WebRTCManager.peer) {
        self.chatRoomId = chatRoomId
        self.currentPeer = currentPeer
    }
    
    var connectionState: AsyncStream<WebRTCManager.webRTCManagerConnectionState> {
        webRTCManager.connectionState
    }
    var connectionStateInfo: AsyncStream<String> {
        webRTCManager.connectionStateInfo
    }
    
    deinit {
        print("WebRTCManager ParticipantViewModel deinit")
    }
    
    func retryConnect() async {
        await webRTCManager.retryConnect(chatRoomId: chatRoomId, currentPeer: currentPeer)
    }
    
    func rtcViewInit(uiView: UIView,containerSize: CGSize) -> UIView {
        let view = webRTCManager.renderRemoteVideo(frame: CGRect(origin: CGPoint(x: 0, y: 0), size: containerSize))!
        webRTCManager.startCaptureLocalVideo()
        return view
    }
}
