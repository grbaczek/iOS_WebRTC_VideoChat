//
//  SessionDescription.swift
//  SimpleUX
//
//  Created by Alina Maksimova on 31.08.21.
//

import Foundation
import WebRTC

enum SdpType: String, Codable {
    case offer, prAnswer, answer

    var rtcSdpType: RTCSdpType {
        switch self {
        case .offer:
            return .offer
        case .answer:
            return .answer
        case .prAnswer:
            return .prAnswer
        }
    }
}

struct SessionDescription: Codable {
    let sdp: String
    let type: SdpType

    var rtcSessionDescription: RTCSessionDescription {
        RTCSessionDescription(type: self.type.rtcSdpType, sdp: self.sdp)
    }

    init(from rtcSessionDescription: RTCSessionDescription) {
        self.sdp = rtcSessionDescription.sdp

        switch rtcSessionDescription.type {
        case .offer:
            self.type = .offer
        case .prAnswer:
            self.type = .prAnswer
        case .answer:
            self.type = .answer
        @unknown default:
            fatalError("Unknown RTCSessionDescription type: \(rtcSessionDescription.type.rawValue)")
        }
    }
}
