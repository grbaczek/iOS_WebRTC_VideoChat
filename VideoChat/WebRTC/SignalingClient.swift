//
//  SignalingClient2.swift
//  SimpleUX
//
//  Created by Grzegorz Baczek on 19/05/2022.
//

import Foundation
import WebRTC
import Firebase
import FirebaseFirestoreSwift

class SignalingClient {
    enum DocumentSnapshotError: Error {
        case documentEmpty
    }

    private let chatRoomCollection = "rooms"
    private let sdpDocument = "sdp"
    private let candidatesDocument = "candidates"
    private let candidateCollection = "candidate"
    private let readyField = "readyForTest"
    private let startRecordingField = "startRecording"
    private let completedTestField = "completedTest"
    lazy var db = Firestore.firestore()

    func getRTCSessionDescriptions(_ collection: String, _ chatRoomId: String) -> AsyncThrowingStream<RTCSessionDescription, Error> {
        AsyncThrowingStream { continuation in
            let listener = getSpdDocument(collection, chatRoomId)
                .addSnapshotListener { documentSnapshot, error in
                    if let document = documentSnapshot, document.exists
                    {
                        do {
                            let sessionDescription: SessionDescription = try document.data(as: SessionDescription.self)
                            continuation.yield(sessionDescription.rtcSessionDescription)
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }
    func getCandidates(_ collection: String, _ chatRoomId: String) -> AsyncThrowingStream<RTCIceCandidate, Error> {
        AsyncThrowingStream { continuation in
            let listener = getCandidatesCollection(collection, chatRoomId)
                .addSnapshotListener { querySnapshot, error in
                    if let querySnapshot = querySnapshot {
                        querySnapshot.documentChanges.forEach { documentChange in
                            if documentChange.type == .added {
                                do {
                                    let iceCandidate = try documentChange.document.data(as: IceCandidate.self)
                                    continuation.yield(iceCandidate.rtcIceCandidate)
                                } catch {
                                    continuation.finish(throwing: error)
                                }
                            }
                        }
                    } else {
                        continuation.finish(throwing: DocumentSnapshotError.documentEmpty)
                    }
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }
    func deleteSpdDocument(_ collection: String, _ chatRoomId: String) async throws {
        try await getSpdDocument(collection, chatRoomId)
            .delete()
    }
    func deleteSdpAndCandidate(collection: String, chatRoomId: String) async throws {
        try await deleteSpdDocument(collection, chatRoomId)
        let candidatesQuerySnapshot = try await getCandidatesCollection(collection, chatRoomId)
            .getDocuments()
        for queryDocumentSnapshot in candidatesQuerySnapshot.documents {
            try await queryDocumentSnapshot.reference.delete()
        }
    }
    func waitUntilSdpAndCandidatesDeleted(collection: String, chatRoomId: String) async throws {
        var sdpDocumentExists = try await getSpdDocument(collection, chatRoomId).getDocument().exists
        var candidatesCollectionExists = try await !getCandidatesCollection(collection, chatRoomId).getDocuments().isEmpty
        while sdpDocumentExists && candidatesCollectionExists {
            try await Task.sleep(nanoseconds: 1_000_000 * 200)
            sdpDocumentExists = try await getSpdDocument(collection, chatRoomId).getDocument().exists
            candidatesCollectionExists = try await !getCandidatesCollection(collection, chatRoomId).getDocuments().isEmpty
        }
    }
    func send(sdp rtcSdp: RTCSessionDescription, chatRoomId: String, collection: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try getSpdDocument(collection, chatRoomId)
                    .setData(
                        from: SessionDescription(from: rtcSdp)
                    ) { error in
                            if let error = error {
                                continuation.resume(with: .failure(error))
                            } else {
                                continuation.resume(with: .success(()))
                            }
                    }
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
    }
    func send(candidate rtcIceCandidate: RTCIceCandidate, chatRoomId: String, collection: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                _ = try getCandidatesCollection(collection, chatRoomId)
                    .addDocument(
                        from: IceCandidate(from: rtcIceCandidate),
                        completion: { error in
                            if let error = error {
                                continuation.resume(with: .failure(error))
                            } else {
                                continuation.resume(with: .success(()))
                            }
                        })
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
    }
    private func getCandidatesCollection(_ collection: String, _ roomId: String) -> CollectionReference {
        getCandidatesDocument(collection, roomId)
            .collection(candidateCollection)
    }
    private func getSpdDocument(_ collection: String, _ roomId: String) -> DocumentReference {
        getChatRoomCollection(collection, roomId)
            .document(sdpDocument)
    }
    private func getCandidatesDocument(_ collection: String, _ roomId: String) -> DocumentReference {
        getChatRoomCollection(collection, roomId)
            .document(candidatesDocument)
    }
    private func getChatRoomCollection(_ collection: String, _ roomId: String) -> CollectionReference {
        db
            .collection(chatRoomCollection)
            .document(roomId)
            .collection(collection)
    }
}
