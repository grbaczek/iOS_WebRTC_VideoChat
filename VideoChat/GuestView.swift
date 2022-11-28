//
//  GuestView.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 20/11/2022.
//

import Foundation
import SwiftUI

struct GuestView: View {
    
    @StateObject var viewModel: ParticipantViewModel
    
    var body: some View {
        VStack {
            Text("Guest, roomId: \(viewModel.chatRoomId)")
        }
    }
}

struct GuestViewPreview: PreviewProvider {
    static var previews: some View {
        GuestView(
            viewModel: ParticipantViewModel(
                chatRoomId: "",
                currentPeer: WebRTCManager.peer.host
            )
        )
    }
}
