//
//  JoinChatRoom.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 20/11/2022.
//

import Foundation
import SwiftUI

class JoinChatRoomViewModel: ObservableObject {
    let videoChatRepository = VideoChatRepository()
    @Published var chatRooms: [(String, ChatRoom)] = []
    var chatRoomsStream: AsyncThrowingStream<[(String, ChatRoom)], Error> {
        get {
            videoChatRepository.getChatRooms()
        }
    }
    
    deinit {
        print("JoinChatRoomViewModel deinit")
    }
}

struct JoinChatRoom: View {
    
    @StateObject var joinChatRoomViewModel = JoinChatRoomViewModel()
    @State var errorMessage: String = ""
    
    var body: some View {
        VStack {
            ScrollView {
                Text(errorMessage)
                    .foregroundColor(.red)
                LazyVStack {
                    ForEach(joinChatRoomViewModel.chatRooms, id: \.0) {  chatRoom in
                        NavigationLink(chatRoom.1.name) {
                            GuestView(
                                viewModel: ParticipantViewModel(
                                    chatRoomId: chatRoom.0,
                                    currentPeer: WebRTCManager.peer.guest
                                )
                            )
                        }
                    }
                }
            }
        }.task {
            do {
                for try await chatRooms in joinChatRoomViewModel.chatRoomsStream {
                    joinChatRoomViewModel.chatRooms = chatRooms
                }
            }
            catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
