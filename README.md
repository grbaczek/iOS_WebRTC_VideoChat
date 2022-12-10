# WebRTC iOS VideoChat

This is an example implementation of iOS WebRTC video VideoChat.

Establishing WebRTC connection consists of multiple asynchronous steps where data is exchanged over the network
* communication with STUN/TURN servers
* communication with signaling servers

 Error handling and connection reset is tricky.  

The project presents:
* approach to establishing a reliable WebRTC connection every time two peers try to connect to each other.
* error handling and reliable connection reset

```Swift
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        for try await rtcSessionDescription in  signalClient.getRTCSessionDescriptions(
            currentPeer.watchKey,
            chatRoomId
        ) {
            try await webRTCClient.set(remoteSdp: rtcSessionDescription)
            connectionStateContainer.info = "Remote SDP set"
            if currentPeer == .guest {
                let sdp = try await webRTCClient.answer()
                try await signalClient.send(sdp: sdp, testId: chatRoomId, collection: currentPeer.sendKey)
                connectionStateContainer.info = "SDP answer sent"
            }
            break
        }
    }
    if currentPeer == .host {
        group.addTask {
            let sdp = try await webRTCClient.offer()
            try await signalClient.send(sdp: sdp, testId: chatRoomId, collection: currentPeer.sendKey)
            connectionStateContainer.info = "SDP offer sent"
        }
    }
    group.addTask {
        for _ in 1...40 {
            if webRTCClient.isRemoteDescriptionSet {
                return
            }
            try await Task.sleep(milliseconds: 100)
        }
        connectionStateContainer.info = "Connection timeout"
        throw connectionError.connectionTimeoutError
    }
    try await group.waitForAll()
}
connectionStateContainer.info = "RTC exchanged"
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        for try await candidate in signalClient.getCandidates(currentPeer.watchKey, chatRoomId) {
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
        try await signalClient.waitUntilSdpAndCandidatesDeleted(
            collection: currentPeer.watchKey,
            testId: chatRoomId)
        connectionStateContainer.info = "Peer connection reset"
        throw connectionError.connectionReset
    }
    try await group.waitForAll()
}
```

Technologies used:
* WebRTC
* Swift programming language
* Swift structured concurrency
* SwiftUI
* Firebase firestore

Core algorithm:



Firebase as signaling server

```mermaid
sequenceDiagram
    participant Host
    participant Firebase
    Host->>Firebase: Create a chat channel
    Host->>Firebase: SDP offer
    Firebase->>Guest: SDP offer
    Guest->>Firebase: SDP answer
    Firebase->>Host: SDP answer
    Host->>Firebase: ICE candidate (Host)
    Firebase->>Guest: ICE candidate (Host)
    Guest->>Firebase: ICE candidate (Guest)
    Firebase->>Host: ICE candidate (Host)
```
