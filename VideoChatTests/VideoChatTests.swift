//
//  VideoChatTests.swift
//  VideoChatTests
//
//  Created by Grzegorz Baczek on 14/11/2022.
//

import XCTest
@testable import VideoChat

final class VideoChatTests: XCTestCase {

    private let testId = "tJn71g0Bi3uh5s7V9cQT"
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    private func simultaneousConnection() async throws {
        await simulateConnection(testId)
    }
    func testSimultaneousConnection() async throws {
        for i in 1...10 {
            try await simultaneousConnection()
            print("facilitator and tester connected - \(i)")
        }
    }
    func facilitatorConnectingFirst() async throws {
        await simulateConnection(testId, testerDelaySec: Int.random(in: 1...5))
    }
    func testFacilitatorConnectingFirst() async throws {
        for i in 1...10 {
            try await facilitatorConnectingFirst()
            print("facilitator and tester connected - \(i)")
        }
    }
    func testerConnectingFirst() async throws {
        await simulateConnection(testId, facilitatorDelaySec: Int.random(in: 1...5))
    }
    func testTesterConnectingFirst() async throws {
        for i in 1...10 {
            try await testerConnectingFirst()
            print("facilitator and tester connected - \(i)")
        }
    }
    func peerReconnected(facilitatorDelaySec: Int = 0, testerDelaySec: Int = 0, interruptedPeer: WebRTCManager.peer) async throws {
        try await simulateInterruptedConnection(
            testId,
            facilitatorDelaySec: facilitatorDelaySec,
            testerDelaySec: testerDelaySec,
            interruptedPeer: interruptedPeer)
    }
    func testTesterDisconnected() async throws {
        for i in 1...100 {
            try await peerReconnected(
                facilitatorDelaySec: Int.random(in: 1...5),
                testerDelaySec: Int.random(in: 1...5),
                interruptedPeer: WebRTCManager.peer.receiver)
            print("facilitator and tester connected - \(i)")
        }
    }

    func testFacilitatorDisconnected() async throws {
        for i in 1...100 {
            try await peerReconnected(
                facilitatorDelaySec: Int.random(in: 1...5),
                testerDelaySec: Int.random(in: 1...5),
                interruptedPeer: WebRTCManager.peer.presenter)
            print("facilitator and tester connected - \(i)")
        }
    }
    func testRandomConnectionScheme() async throws {
        for i in 1...100 {
            let randomTestCase = Int.random(in: 1...5)
            switch randomTestCase {
            case 1:
                print("\(i) facilitator and tester simultaneousConnection")
                try await simultaneousConnection()
                print("\(i) facilitator and tester connected - simultaneousConnection")
            case 2:
                print("\(i) facilitator and tester facilitatorConnectingFirst")
                try await facilitatorConnectingFirst()
                print("\(i) facilitator and tester connected - facilitatorConnectingFirst")
            case 3:
                print("\(i) facilitator and tester testerConnectingFirst")
                try await testerConnectingFirst()
                print("\(i) facilitator and tester connected - testerConnectingFirst")
            case 4:
                print("\(i) facilitator and tester peerReconnected receiver")
                try await peerReconnected(
                    facilitatorDelaySec: Int.random(in: 1...5),
                    testerDelaySec: Int.random(in: 1...5),
                    interruptedPeer: WebRTCManager.peer.receiver)
                print("\(i) facilitator and tester connected - peerReconnected receiver")
            default:
                print("\(i) facilitator and tester peerReconnected presenter")
                try await peerReconnected(
                    facilitatorDelaySec: Int.random(in: 1...5),
                    testerDelaySec: Int.random(in: 1...5),
                    interruptedPeer: WebRTCManager.peer.presenter)
                print("\(i) facilitator and tester connected - peerReconnected presenter")
            }
        }
    }
    private func simulateConnection(_ testId: String, facilitatorDelaySec: Int = 0, testerDelaySec: Int = 0) async {
        let testerWebRTCManager = WebRTCManager()
        let facilitatorWebRTCManager = WebRTCManager()
        let t = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(facilitatorDelaySec))
            await testerWebRTCManager.retryConnect(testId: testId, currentPeer: WebRTCManager.peer.presenter)
        }
        let t2 = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(testerDelaySec))
            await facilitatorWebRTCManager.retryConnect(testId: testId, currentPeer: WebRTCManager.peer.receiver)
        }
        let t3 = Task {
            for await connectionState in testerWebRTCManager.connectionState {
                if connectionState == .connected {
                    t.cancel()
                    break
                }
            }
        }
        let t4 = Task {
            for await connectionState in facilitatorWebRTCManager.connectionState {
                if connectionState == .connected {
                    t2.cancel()
                    break
                }
            }
        }
        await t3.value
        await t4.value
    }
    private func simulateInterruptedConnection(_ testId: String, facilitatorDelaySec: Int = 0, testerDelaySec: Int = 0, interruptedPeer: WebRTCManager.peer) async throws {
        let testerWebRTCManager = WebRTCManager()
        let facilitatorWebRTCManager = WebRTCManager()
        let connectPeer: (WebRTCManager.peer, Int) async throws -> Void = { peer, delaySec in
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(delaySec))
            let webRTCManager = peer == WebRTCManager.peer.presenter ? facilitatorWebRTCManager : testerWebRTCManager
            await webRTCManager.retryConnect(testId: testId, currentPeer: peer)
        }
        let waitForConnection: (WebRTCManager.peer, () async throws -> Void) async throws -> Void = { peer, connectedCallback in
            let webRTCManager = peer == WebRTCManager.peer.presenter ? facilitatorWebRTCManager : testerWebRTCManager
            for await connectionState in webRTCManager.connectionState {
                if connectionState == .connected {
                    try await connectedCallback()
                    break
                }
            }
        }
        let presenterConnectionTask = Task {
            try await connectPeer(WebRTCManager.peer.presenter, facilitatorDelaySec)
        }
        let receiverConnectionTask = Task {
            try await connectPeer(WebRTCManager.peer.receiver, testerDelaySec)
        }
        let t4 = Task {
            try await waitForConnection(WebRTCManager.peer.receiver) {
                if interruptedPeer == WebRTCManager.peer.receiver {
                    receiverConnectionTask.cancel()
                }
            }
        }
        let t3 = Task {
            try await waitForConnection(WebRTCManager.peer.presenter) {
                if interruptedPeer == WebRTCManager.peer.presenter {
                    presenterConnectionTask.cancel()
                }
            }
        }
        try await t4.value
        try await t3.value
        // allow disconnected state to propagate
        try await Task.sleep(nanoseconds: 100_000_000 * 2)
        let t5 = Task {
            try await connectPeer(interruptedPeer, interruptedPeer == WebRTCManager.peer.receiver ? testerDelaySec : facilitatorDelaySec)
        }
        let t6 = Task {
            try await waitForConnection(interruptedPeer) {
                t5.cancel()
            }
        }
        let t7 = Task {
            let peer = interruptedPeer == WebRTCManager.peer.receiver ? WebRTCManager.peer.presenter : WebRTCManager.peer.receiver
            try await waitForConnection(peer) {
                let taskToCancel = interruptedPeer == WebRTCManager.peer.receiver ?  presenterConnectionTask : receiverConnectionTask
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
