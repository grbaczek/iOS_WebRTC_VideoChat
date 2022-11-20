//
//  VideoChatRepository.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 19/11/2022.
//

import Foundation
import Firebase
import FirebaseFirestoreSwift

class VideoChatRepository {
    
    private let db = Firestore.firestore()
    private let roomsCollectionPath = "rooms"
    private let roomCollectionNameKey = "name"
    private let roomCollectionIdKey = "id"
    
    func createChatRoom(chatRoomName: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection(roomsCollectionPath).addDocument(data: [
                roomCollectionNameKey : chatRoomName
            ]) { err in
                if let err = err {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func getChatRooms() -> AsyncThrowingStream<[(String, ChatRoom)], Error> {
        AsyncThrowingStream { continuation in
            db.collection(roomsCollectionPath).addSnapshotListener { snapshot, error in
                if let snapshot = snapshot {
                    var lst: [(String, ChatRoom)] = []
                    snapshot.documents.forEach { doc in
                        do {
                            let chatRoom = try doc.data(as: ChatRoom.self)
                            lst.append((doc.documentID, chatRoom))
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.yield(lst)
                } else if let err = error {
                    continuation.finish(throwing: err)
                }
            }
        }
    }
}
