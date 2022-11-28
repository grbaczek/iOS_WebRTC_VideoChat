//
//  HostView.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 20/11/2022.
//

import Foundation
import SwiftUI

struct HostView: View {
    
    @StateObject var viewModel: ParticipantViewModel
    
    var body: some View {
        VStack {
            Text("Host, room id \(viewModel.chatRoomId)")
        }
    }
}

struct HostViewPreview: PreviewProvider {
    static var previews: some View {
        HostView(
            viewModel: ParticipantViewModel(
                chatRoomId: "",
                currentPeer: WebRTCManager.peer.host
            )
        )
    }
}
