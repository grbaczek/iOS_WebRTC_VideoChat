//
//  WebRTCManager.swift
//  SimpleUX
//
//  Created by Grzegorz Baczek on 05/06/2022.
//

import Combine
import Foundation
import ReplayKit
import UIKit

public class WebRTCManager {
    enum peer: String {
        case guest
        case host

        var sendKey: String {
            switch self {
            case .guest:
                return "guest"
            case .host:
                return "host"
            }
        }
        var watchKey: String {
            switch self {
            case .guest:
                return "host"
            case .host:
                return "guest"
            }
        }
    }
    enum webRTCManagerConnectionState {
        case connected
        case disconnected
    }
    class ConnectionStateContainer {
        @Published var state = webRTCManagerConnectionState.disconnected
        @Published var info = "Idle"
    }
    enum connectionError: Error {
        case connectionTimeoutError
        case connectionReset
        case connectionFailed
    }

    var connectionState: AsyncStream<webRTCManagerConnectionState> {
        AsyncStream {  continuation in
            let subscription = connectionStateContainer.$state
                .sink(receiveValue: { connectionState in
                    continuation.yield(connectionState)
                })
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }
    var connectionStateInfo: AsyncStream<String> {
        AsyncStream {  continuation in
            let subscription = connectionStateContainer.$info
                .sink(receiveValue: { info in
                    continuation.yield(info)
                })
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }
    
    private var connectionStateContainer = ConnectionStateContainer()
    private var webRTCClient: WebRTCClient?

    deinit {
        print("WebRTCManager deinit")
    }

    func retryConnect(chatRoomId: String, currentPeer: peer, preConnectionCallback: (() async throws -> Void)? = nil) async {
        defer {
            webRTCClient?.closePeerConnection()
            connectionStateContainer.state = webRTCManagerConnectionState.disconnected
        }
        while true {
            do {
                if Task.isCancelled {
                    return
                }
                try await connect(
                    chatRoomId: chatRoomId,
                    currentPeer: currentPeer,
                    preConnectionCallback: preConnectionCallback
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                connectionStateContainer.info = "retry connection cancelled"
                return
            } catch {
                print(error.localizedDescription)
                connectionStateContainer.state = webRTCManagerConnectionState.disconnected
                webRTCClient?.closePeerConnection()
            }
        }
    }
    func renderRemoteVideo(frame: CGRect) -> UIView? {
        webRTCClient?.renderRemoteVideo(frame: frame)
    }
    
    func startCaptureLocalVideo() {
        webRTCClient?.startCaptureLocalVideo()
    }
    private func connect(chatRoomId: String, currentPeer: peer, preConnectionCallback: (() async throws -> Void)? = nil) async throws {
        connectionStateContainer.info = "connect called"
        webRTCClient?.closePeerConnection()
        let signalingClient = SignalingClient()
        try await signalingClient.deleteSdpAndCandidate(collection: currentPeer.sendKey, chatRoomId: chatRoomId)
        try await signalingClient.waitUntilSdpAndCandidatesDeleted(collection: currentPeer.watchKey, chatRoomId: chatRoomId)
        connectionStateContainer.info = "SDP and candidate data cleared"
        let webRTCClient = try WebRTCClient()
        try webRTCClient.createPeerConnection()
        self.webRTCClient = webRTCClient
        let connectionStateContainer = connectionStateContainer

        try await preConnectionCallback?()
        let connectedTask = Task {
            for await state in webRTCClient.getConnectionState() {
                if state == .connected || state == .completed {
                    connectionStateContainer.info = "Connected"
                    connectionStateContainer.state = .connected
                    speakerOn()
                } else {
                    connectionStateContainer.info = "Disconnected"
                    connectionStateContainer.state = .disconnected
                    speakerOff()
                }
            }
        }
        let candidateTask = Task {
            for try await candidate in webRTCClient.getCandidates() {
                try await signalingClient.send(candidate: candidate, chatRoomId: chatRoomId, collection: currentPeer.sendKey)
            }
        }
        defer {
            connectedTask.cancel()
            candidateTask.cancel()
        }
        // exchange rtc first: https://webrtc.org/getting-started/peer-connections
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await rtcSessionDescription in signalingClient.getRTCSessionDescriptions(
                    currentPeer.watchKey,
                    chatRoomId
                ) {
                    try await webRTCClient.set(remoteSdp: rtcSessionDescription)
                    connectionStateContainer.info = "Remote SDP set"
                    if currentPeer == .guest {
                        let sdp = try await webRTCClient.answer()
                        try await signalingClient.send(sdp: sdp, chatRoomId: chatRoomId, collection: currentPeer.sendKey)
                        connectionStateContainer.info = "SDP answer sent"
                    }
                    break
                }
            }
            if currentPeer == .host {
                group.addTask {
                    let sdp = try await webRTCClient.offer()
                    try await signalingClient.send(sdp: sdp, chatRoomId: chatRoomId, collection: currentPeer.sendKey)
                    connectionStateContainer.info = "SDP offer sent"
                }
            }
            group.addTask {
                for _ in 1...120 {
                    if webRTCClient.isRemoteDescriptionSet {
                        return
                    }
                    try await Task.sleep(milliseconds: 100)
                }
                connectionStateContainer.info = "Connection timeout"
                throw connectionError.connectionTimeoutError
            }
            try await group.waitForAllToCompleteOrAnyToFail()
        }
        connectionStateContainer.info = "RTC exchanged"
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await candidate in signalingClient.getCandidates(currentPeer.watchKey, chatRoomId) {
                    try await webRTCClient.set(remoteCandidate: candidate)
                }
                connectionStateContainer.info = "Candidates set"
            }
            group.addTask {
                for await state in webRTCClient.getConnectionState() where state == .failed {
                    connectionStateContainer.info = "Connection failed"
                    throw connectionError.connectionFailed
                }
            }
            group.addTask {
                try await Task.sleep(seconds: 15)
                if connectionStateContainer.state != .connected {
                    connectionStateContainer.info = "Connection timeout"
                    throw connectionError.connectionTimeoutError
                }
            }
            group.addTask {
                // peer has deleted sdp and candidates - reset connection
                try await signalingClient.waitUntilSdpAndCandidatesDeleted(
                    collection: currentPeer.watchKey,
                    chatRoomId: chatRoomId)
                connectionStateContainer.info = "Peer connection reset"
                throw connectionError.connectionReset
            }
            try await group.waitForAllToCompleteOrAnyToFail()
        }
    }
    func muteAudio() {
        webRTCClient?.muteAudio()
    }

    func unmuteAudio() {
        webRTCClient?.unmuteAudio()
    }

    // Fallback to the default playing device: headphones/bluetooth/ear speaker
    func speakerOff() {
        webRTCClient?.speakerOff()
    }

    // Force speaker
    func speakerOn() {
        #if !DEBUG
        webRTCClient?.speakerOn()
        #endif
    }
}

extension ThrowingTaskGroup<Void, Error> {
    mutating func waitForAllToCompleteOrAnyToFail() async throws {
        while !isEmpty {
            do {
                try await next()
            } catch is CancellationError {
                // we decide that cancellation errors thrown by children,
                // should not cause cancellation of the entire group.
                continue
            }
        }
    }
}


extension Task where Success == Never, Failure == Never {
    static func sleep(milliseconds: UInt64) async throws {
        try await sleep(nanoseconds: milliseconds * 1_000_000)
    }
    static func sleep(seconds: UInt64) async throws {
        try await sleep(nanoseconds: seconds * 1_000_000_000)
    }
}
