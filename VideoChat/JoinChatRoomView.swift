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

struct JoinChatRoomView: View {
    
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
                            PickParticipantView(
                                chatRoomId: chatRoom.0,
                                chatRoomName: chatRoom.1.name
                            )
                            .navigationTitle("Pick participant")
                        }
                        .padding()
                    }
                }
                .padding()
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
