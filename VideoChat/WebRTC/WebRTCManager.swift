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
    private var connectionStateContainer = ConnectionStateContainer()
    private var webRTCClient: WebRTCClient?

    deinit {
        print("WebRTCManager deinit")
    }

    func retryConnect(testId: String, currentPeer: peer, preConnectionCallback: (() async throws -> Void)? = nil) async {
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
                    testId: testId,
                    currentPeer: currentPeer,
                    preConnectionCallback: preConnectionCallback
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                print("retryConnect cancelled")
                return
            } catch {
                print(error.localizedDescription)
                connectionStateContainer.state = webRTCManagerConnectionState.disconnected
                webRTCClient?.closePeerConnection()
            }
        }
    }
    func captureCurrentFrame(sampleBuffer: CMSampleBuffer) {
        webRTCClient?.captureCurrentFrame(sampleBuffer: sampleBuffer)
    }
    func renderRemoteVideo(to view: UIView) -> UIView? {
        webRTCClient?.renderRemoteVideo(view: view)
    }
    private func connect(testId: String, currentPeer: peer, preConnectionCallback: (() async throws -> Void)? = nil) async throws {
        webRTCClient?.closePeerConnection()
        let signalClient = SignalingClient()
        try await signalClient.deleteSdpAndCandidate(collection: currentPeer.sendKey, testId: testId)
        try await signalClient.waitUntilSdpAndCandidatesDeleted(collection: currentPeer.watchKey, testId: testId)
        let webRTCClient = try WebRTCClient()
        try webRTCClient.createPeerConnection()
        self.webRTCClient = webRTCClient
        let connectionStateContainer = connectionStateContainer

        try await preConnectionCallback?()
        let connectedTask = Task {
            for await state in webRTCClient.getConnectionState() {
                if state == .connected || state == .completed {
                    connectionStateContainer.state = .connected
                    speakerOn()
                } else {
                    connectionStateContainer.state = .disconnected
                    speakerOff()
                }
            }
        }
        let candidateTask = Task {
            for try await candidate in webRTCClient.getCandidates() {
                try await signalClient.send(candidate: candidate, testId: testId, collection: currentPeer.sendKey)
            }
        }
        defer {
            connectedTask.cancel()
            candidateTask.cancel()
        }
        // exchange rtc first: https://webrtc.org/getting-started/peer-connections
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await rtcSessionDescription in  signalClient.getRTCSessionDescriptions(
                    currentPeer.watchKey,
                    testId) {
                    try await webRTCClient.set(remoteSdp: rtcSessionDescription)
                    if currentPeer == .guest {
                        let sdp = try await webRTCClient.answer()
                        try await signalClient.send(sdp: sdp, testId: testId, collection: currentPeer.sendKey)
                    }
                    break
                }
            }
            if currentPeer == .host {
                group.addTask {
                    let sdp = try await webRTCClient.offer()
                    try await signalClient.send(sdp: sdp, testId: testId, collection: currentPeer.sendKey)
                }
            }
            group.addTask {
                for _ in 1...40 {
                    if webRTCClient.isRemoteDescriptionSet {
                        return
                    }
                    try await Task.sleep(milliseconds: 100)
                }
                throw connectionError.connectionTimeoutError
            }
            try await group.waitForAll()
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await candidate in signalClient.getCandidates(currentPeer.watchKey, testId) {
                    try await webRTCClient.set(remoteCandidate: candidate)
                }
            }
            group.addTask {
                for await state in webRTCClient.getConnectionState() where state == .failed {
                    throw connectionError.connectionFailed
                }
            }
            group.addTask {
                try await Task.sleep(seconds: 15)
                if connectionStateContainer.state != .connected {
                    throw connectionError.connectionTimeoutError
                }
            }
            group.addTask {
                // peer has deleted sdp and candidates - reset connection
                try await signalClient.waitUntilSdpAndCandidatesDeleted(
                    collection: currentPeer.watchKey,
                    testId: testId)
                throw connectionError.connectionReset
            }
            try await group.waitForAll()
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

extension Task where Success == Never, Failure == Never {
    static func sleep(milliseconds: UInt64) async throws {
        try await sleep(nanoseconds: milliseconds * 1_000_000)
    }
    static func sleep(seconds: UInt64) async throws {
        try await sleep(nanoseconds: seconds * 1_000_000_000)
    }
}
