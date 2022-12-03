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
    @State var connectionStateInfo: String = ""
    
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
                        Spacer()
                        HStack{
                            Spacer()
                            Text(connectionStateInfo)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .task {
            await viewModel.retryConnect()
        }
        .task {
            for await connectionState in viewModel.connectionState {
                withAnimation {
                    self.connectionState = connectionState
                }
            }
        }
        .task {
            for await connectionStateInfo in viewModel.connectionStateInfo {
                withAnimation {
                    self.connectionStateInfo = connectionStateInfo
                }
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
