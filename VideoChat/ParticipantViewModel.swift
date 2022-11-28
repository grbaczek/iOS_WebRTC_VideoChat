//
//  ParticipantViewModel.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 28/11/2022.
//

import Foundation

@MainActor
class ParticipantViewModel: ObservableObject {
    
    private var webRTCManager = WebRTCManager()
    private var currentPeer: WebRTCManager.peer
    let chatRoomId: String
    @Published var connectionState: WebRTCManager.webRTCManagerConnectionState = .disconnected
    
    init(chatRoomId: String, currentPeer: WebRTCManager.peer) {
        self.chatRoomId = chatRoomId
        self.currentPeer = currentPeer
        
        Task { [weak self] in
            for await connectionState in webRTCManager.connectionState {
                self?.connectionState = connectionState
            }
        }
    }
    
    func retryConnect() async {
        await webRTCManager.retryConnect(chatRoomId: chatRoomId, currentPeer: currentPeer)
    }
}
