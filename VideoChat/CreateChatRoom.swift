//
//  CreateChatRoom.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 20/11/2022.
//

import Foundation
import SwiftUI

class CreateChatRoomViewModel: ObservableObject {
    private let videoChatRepository = VideoChatRepository()
    
    func createChatRoom(chatRoomName: String) async throws {
        try await videoChatRepository.createChatRoom(chatRoomName: chatRoomName)
    }
}

struct CreateChatRoom: View {
    
    @State var chatRoomName: String = ""
    @State var errorMessage: String = ""
    @State var creatingChatRoom: Bool = false
    @State var roomCreated: Bool = false
    @StateObject var createChatRoomViewModel = CreateChatRoomViewModel()
    
    var body: some View {
        VStack {
            Spacer()
            TextField("Chat room name", text: $chatRoomName , prompt: Text("Enter chat room name"))
            Text(errorMessage)
                .foregroundColor(.red)
            Spacer()
            HStack {
                Spacer()
                NavigationLink(
                    "",
                    destination: HostView(),
                    isActive: $roomCreated
                )
                Button("Next", action: {
                    creatingChatRoom = true
                    Task {
                        errorMessage = ""
                        do {
                            try await createChatRoomViewModel.createChatRoom(chatRoomName: chatRoomName)
                            roomCreated = true
                        }
                        catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    creatingChatRoom = false
                })
                .disabled(chatRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomCreated)
            }
        }
        .padding([.trailing, .leading, .bottom], 32)
        .onChange(of: roomCreated) { value in
            if !value {
                chatRoomName = ""
            }
        }
    }
}
