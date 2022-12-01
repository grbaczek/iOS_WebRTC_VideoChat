//
//  GuestView.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 20/11/2022.
//

import Foundation
import SwiftUI

struct ParticipantView: View {
    
    @StateObject var viewModel: ParticipantViewModel
    @State var connectionState: WebRTCManager.webRTCManagerConnectionState = .disconnected
    
    var body: some View {
        GeometryReader { reader in
            ZStack {
                if connectionState == .connected {
                    RtcVideoView(
                        containerSize: reader.size,
                        rtcViewInit: viewModel.rtcViewInit
                    )
                } else {
                    VStack {
                        Text("\(viewModel.currentPeer.rawValue), roomId: \(viewModel.chatRoomId)")
                    }
                }
            }
        }
        .task {
            await viewModel.retryConnect()
        }
        .onChange(of: viewModel.connectionState) { value in
            withAnimation{
                connectionState = value
            }
        }
    }
}

struct GuestViewPreview: PreviewProvider {
    static var previews: some View {
        ParticipantView(
            viewModel: ParticipantViewModel(
                chatRoomId: "",
                currentPeer: WebRTCManager.peer.host
            )
        )
    }
}
