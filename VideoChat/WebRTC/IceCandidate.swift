//
//  IceCandidate.swift
//  SimpleUX
//
//  Created by Alina Maksimova on 31.08.21.
//

import Foundation
import WebRTC

struct IceCandidate: Codable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?

    var rtcIceCandidate: RTCIceCandidate {
        RTCIceCandidate(sdp: self.sdp, sdpMLineIndex: self.sdpMLineIndex, sdpMid: self.sdpMid)
    }

    init(from iceCandidate: RTCIceCandidate) {
        self.sdpMLineIndex = iceCandidate.sdpMLineIndex
        self.sdpMid = iceCandidate.sdpMid
        self.sdp = iceCandidate.sdp
    }
}
