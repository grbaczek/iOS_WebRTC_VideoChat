//
//  VideoChatTests.swift
//  VideoChatTests
//
//  Created by Grzegorz Baczek on 14/11/2022.
//

import XCTest
@testable import VideoChat

final class VideoChatTests: XCTestCase {
    
    let videoChatRepository = VideoChatRepository()

    private var chatRoomId: String {
        get async throws {
           try await videoChatRepository.createChatRoom(chatRoomName: "Unit test")
        }
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    private func simultaneousConnection() async throws {
        await simulateConnection(try await chatRoomId)
    }
    func testSimultaneousConnection() async throws {
        for i in 1...10 {
            try await simultaneousConnection()
            print("connection established - \(i)")
        }
    }
    func guestConnectingFirst() async throws {
        await simulateConnection(try await chatRoomId, hostDelaySec: Int.random(in: 1...5))
    }
    func testGuestConnectingFirst() async throws {
        for i in 1...10 {
            try await guestConnectingFirst()
            print("connection established - \(i)")
        }
    }
    func hostConnectingFirst() async throws {
        await simulateConnection(try await chatRoomId, guestDelaySec: Int.random(in: 1...5))
    }
    func testHostConnectingFirst() async throws {
        for i in 1...10 {
            try await hostConnectingFirst()
            print("connection established  - \(i)")
        }
    }
    func peerReconnected(hostDelaySec: Int = 0, guestDelaySec: Int = 0, interruptedPeer: WebRTCManager.peer) async throws {
        try await simulateInterruptedConnection(
            chatRoomId,
            hostDelaySec: hostDelaySec,
            guestDelaySec: guestDelaySec,
            interruptedPeer: interruptedPeer)
    }
    func testHostDisconnected() async throws {
        for i in 1...10 {
            try await peerReconnected(
                hostDelaySec: Int.random(in: 1...5),
                guestDelaySec: Int.random(in: 1...5),
                interruptedPeer: WebRTCManager.peer.host)
            print("connection established  - \(i)")
        }
    }

    func testGuestDisconnected() async throws {
        for i in 1...10 {
            try await peerReconnected(
                hostDelaySec: Int.random(in: 1...5),
                guestDelaySec: Int.random(in: 1...5),
                interruptedPeer: WebRTCManager.peer.guest)
            print("connection established  - \(i)")
        }
    }
    func testRandomConnectionScheme() async throws {
        for i in 1...10 {
            let randomTestCase = Int.random(in: 1...5)
            switch randomTestCase {
            case 1:
                try await simultaneousConnection()
                print("\(i) connection established ")
            case 2:
                try await guestConnectingFirst()
                print("\(i) connection established ")
            case 3:
                try await hostConnectingFirst()
                print("\(i) connection established ")
            case 4:
                try await peerReconnected(
                    hostDelaySec: Int.random(in: 1...5),
                    guestDelaySec: Int.random(in: 1...5),
                    interruptedPeer: WebRTCManager.peer.guest)
                print("\(i) connection established ")
            default:
                try await peerReconnected(
                    hostDelaySec: Int.random(in: 1...5),
                    guestDelaySec: Int.random(in: 1...5),
                    interruptedPeer: WebRTCManager.peer.host)
                print("\(i) connection established ")
            }
        }
    }
    private func simulateConnection(
        _ chatRoomId: String,
        guestDelaySec: Int = 0,
        hostDelaySec: Int = 0) async
    {
        let guestWebRTCManager = WebRTCManager()
        let hostWebRTCManager = WebRTCManager()
        let t = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(guestDelaySec))
            await guestWebRTCManager.retryConnect(
                chatRoomId: chatRoomId,
                currentPeer: WebRTCManager.peer.guest
            )
        }
        let t2 = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(hostDelaySec))
            await hostWebRTCManager.retryConnect(
                chatRoomId: chatRoomId,
                currentPeer: WebRTCManager.peer.host
            )
        }
        let t3 = Task {
            for await connectionState in guestWebRTCManager.connectionState {
                if connectionState == .connected {
                    t.cancel()
                    break
                }
            }
        }
        let t4 = Task {
            for await connectionState in hostWebRTCManager.connectionState {
                if connectionState == .connected {
                    t2.cancel()
                    break
                }
            }
        }
        await t3.value
        await t4.value
    }
    private func simulateInterruptedConnection(_ chatRoomId: String, hostDelaySec: Int = 0, guestDelaySec: Int = 0, interruptedPeer: WebRTCManager.peer) async throws {
        let guestWebRTCManager = WebRTCManager()
        let hostWebRTCManager = WebRTCManager()
        let connectPeer: (WebRTCManager.peer, Int) async throws -> Void = { peer, delaySec in
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(delaySec))
            let webRTCManager = peer == WebRTCManager.peer.host ? hostWebRTCManager : guestWebRTCManager
            await webRTCManager.retryConnect(chatRoomId: chatRoomId, currentPeer: peer)
        }
        let waitForConnection: (WebRTCManager.peer, () async throws -> Void) async throws -> Void = { peer, connectedCallback in
            let webRTCManager = peer == WebRTCManager.peer.host ? hostWebRTCManager : guestWebRTCManager
            for await connectionState in webRTCManager.connectionState {
                if connectionState == .connected {
                    try await connectedCallback()
                    break
                }
            }
        }
        let hostConnectionTask = Task {
            try await connectPeer(WebRTCManager.peer.host, hostDelaySec)
        }
        let guestConnectionTask = Task {
            try await connectPeer(WebRTCManager.peer.guest, guestDelaySec)
        }
        let t4 = Task {
            try await waitForConnection(WebRTCManager.peer.guest) {
                if interruptedPeer == WebRTCManager.peer.guest {
                    guestConnectionTask.cancel()
                }
            }
        }
        let t3 = Task {
            try await waitForConnection(WebRTCManager.peer.host) {
                if interruptedPeer == WebRTCManager.peer.host {
                    hostConnectionTask.cancel()
                }
            }
        }
        try await t4.value
        try await t3.value
        // allow disconnected state to propagate
        try await Task.sleep(nanoseconds: 100_000_000 * 2)
        let t5 = Task {
            try await connectPeer(interruptedPeer, interruptedPeer == WebRTCManager.peer.guest ? guestDelaySec : hostDelaySec)
        }
        let t6 = Task {
            try await waitForConnection(interruptedPeer) {
                t5.cancel()
            }
        }
        let t7 = Task {
            let peer = interruptedPeer == WebRTCManager.peer.guest ? WebRTCManager.peer.host : WebRTCManager.peer.guest
            try await waitForConnection(peer) {
                let taskToCancel = interruptedPeer == WebRTCManager.peer.guest ?  hostConnectionTask : guestConnectionTask
                taskToCancel.cancel()
            }
        }
        try await t6.value
        try await t7.value
    }
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
