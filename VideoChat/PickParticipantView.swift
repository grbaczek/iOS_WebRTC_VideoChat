//
//  PickParticipant.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 03/12/2022.
//

import Foundation
import SwiftUI

struct PickParticipantView: View {
    
    let chatRoomId: String
    let chatRoomName: String
    
    var body: some View {
        VStack {
            Spacer()
            NavigationLink("Guest") {
                ParticipantView(
                    viewModel: ParticipantViewModel(
                        chatRoomId: chatRoomId,
                        currentPeer: WebRTCManager.peer.guest
                    )
                )
                .navigationTitle("Guest \(chatRoomName)")
            }
            .padding()
            NavigationLink("Host") {
                ParticipantView(
                    viewModel: ParticipantViewModel(
                        chatRoomId: chatRoomId,
                        currentPeer: WebRTCManager.peer.host
                    )
                )
                .navigationTitle("Host \(chatRoomName)")
            }
            .padding()
            Spacer()
        }
    }
}
