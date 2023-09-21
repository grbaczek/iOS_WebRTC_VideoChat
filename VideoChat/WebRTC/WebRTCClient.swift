//
//  WebRTCService2.swift
//  SimpleUX
//
//  Created by Grzegorz Baczek on 15/05/2022.
//

import Accelerate
import Combine
import CoreMedia
import Foundation
import WebRTC

class WebRTCClient: NSObject {
    enum peerConnectionError: Error {
        case peerConnectionNotInitialized
        case sdpNull
        case peerCollectionAlreadyInitialized
    }

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        videoEncoderFactory.preferredCodec = RTCVideoCodecInfo(name: kRTCVideoCodecVp9Name)
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()

    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    private let mediaConstrains = [
        kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
    ]
    private var videoCapturer: RTCVideoCapturer?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var remoteDataChannel: RTCDataChannel?
    private var source: RTCVideoSource?
    private var iceServers: [String]
    private var peerConnection: RTCPeerConnection?
    var audioRecorder: AVAudioRecorder?
    @Published private var connectionState: RTCIceConnectionState?
    private var candidateSubject = PassthroughSubject<RTCIceCandidate, Never>()
    private let peerConnectionSemaphore = DispatchSemaphore(value: 1)
    private let audioQueue = DispatchQueue(label: "audio")
    private let fps: Int32 = 60
    private var videoSourceSizeInitialized = false
    var isRemoteDescriptionSet: Bool {
        peerConnection?.remoteDescription != nil
    }

    init(iceServers: [String] = Config.default.webRTCIceServers) throws {
        self.iceServers = iceServers
        super.init()
    }

    deinit {
        print("WebRTCClientAsync deinit")
    }

    func getConnectionState() -> AsyncStream<RTCIceConnectionState> {
        AsyncStream {  continuation in
            let subscription = $connectionState
                .sink(receiveValue: { connectionState in
                    if let connectionState = connectionState {
                        continuation.yield(connectionState)
                    }
                })
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }
    func getCandidates() -> AsyncStream<RTCIceCandidate> {
        AsyncStream { continuation in
            let subscription = candidateSubject
                .sink(receiveValue: { candidate in
                    continuation.yield(candidate)
                })
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }

    func createPeerConnection() throws {
        RTCSetMinDebugLogLevel(.info)
        peerConnectionSemaphore.wait()
        defer {
            peerConnectionSemaphore.signal()
        }
        if peerConnection != nil {
            throw peerConnectionError.peerCollectionAlreadyInitialized
        }
        let config = RTCConfiguration()

        config.iceServers = [
            RTCIceServer(
                urlStrings: [
                    "stun:stun.l.google.com:19302",
                    "stun:stun1.l.google.com:19302",
                    "stun:stun2.l.google.com:19302",
                    "stun:stun3.l.google.com:19302",
                    "stun:stun4.l.google.com:19302"
                ]
            )
        ]
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        self.peerConnection = WebRTCClient.factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self)
        try self.createMediaSenders()
    }
    func answer() async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        let constrains = RTCMediaConstraints(
            mandatoryConstraints: self.mediaConstrains,
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.answer(for: constrains) { sdp, _ in
                if let sdp = sdp {
                    peerConnection.setLocalDescription(sdp, completionHandler: { _ in
                        continuation.resume(returning: sdp)
                    })
                } else {
                    continuation.resume(throwing: peerConnectionError.sdpNull)
                }
            }
        }
    }
    func offer() async throws -> RTCSessionDescription {
        let constrains = RTCMediaConstraints(
            mandatoryConstraints: self.mediaConstrains,
            optionalConstraints: nil
        )
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        return try await withCheckedThrowingContinuation {( continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.offer(for: constrains) { sdp, _ in
                if let sdp = sdp {
                    peerConnection.setLocalDescription(sdp, completionHandler: { _ in
                        continuation.resume(returning: sdp)
                    })
                } else {
                    continuation.resume(throwing: peerConnectionError.sdpNull)
                }
            }
        }
    }
    // MARK: Media
   
    func renderRemoteVideo(frame: CGRect) -> UIView {
        #if arch(arm64)
            let remoteRenderer = RTCMTLVideoView(frame: frame)
            remoteRenderer.videoContentMode = .scaleAspectFit
        #else
            let remoteRenderer = RTCEAGLVideoView(frame: frame)
        #endif
        self.remoteVideoTrack?.add(remoteRenderer)
        return remoteRenderer
    }
    
    func startCaptureLocalVideo() {
      guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
        return
      }
      
      guard let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),
        // choose highest res
        let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
          let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
          let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
          return width1 < width2
        }).last,
        // choose highest fps
        let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
          return
      }
      
      capturer.startCapture(with: frontCamera,
                            format: format,
                            fps: Int(fps.maxFrameRate))
      
      //self.localVideoTrack?.add(renderer)
    }
    
    func closePeerConnection() {
        peerConnection?.close()
    }
    func set(remoteSdp: RTCSessionDescription) async throws {
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>)  in
            peerConnection.setRemoteDescription(remoteSdp, completionHandler: {error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    func set(remoteCandidate: RTCIceCandidate) async throws {
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        try await peerConnection.add(remoteCandidate)
    }
    private func createMediaSenders() throws {
        let streamId = "stream"
        guard let peerConnection = peerConnection else {
            throw peerConnectionError.peerConnectionNotInitialized
        }
        // Audio
        let audioTrack = self.createAudioTrack()
        peerConnection.add(audioTrack, streamIds: [streamId])
        // Video
        let videoTrack = self.createVideoTrack()
        self.localVideoTrack = videoTrack
        peerConnection.add(videoTrack, streamIds: [streamId])
        self.remoteVideoTrack =
        peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
    }

    // MARK: Data Channels
    private func createDataChannel() -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        guard let dataChannel = self.peerConnection!.dataChannel(forLabel: "WebRTCData", configuration: config) else {
            debugPrint("Warning: Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }

    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: audioConstrains)
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }

    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = WebRTCClient.factory.videoSource()
        #if TARGET_OS_SIMULATOR
        self.videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
        #else
        self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        #endif
        //self.videoCapturer = RTCCustomFrameCapturer(delegate: videoSource)
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        return videoTrack
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        self.connectionState = newState
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.candidateSubject.send(candidate)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.remoteDataChannel = dataChannel
    }
}

extension WebRTCClient {
    private func setTrackEnabled<T: RTCMediaStreamTrack>(_ type: T.Type, isEnabled: Bool) {
        guard let peerConnection = peerConnection else { return }
        peerConnection.transceivers
            .compactMap { $0.sender.track as? T }
            .forEach { $0.isEnabled = isEnabled }
    }
}

// MARK: - Video control
extension WebRTCClient {
    func hideVideo() {
        self.setVideoEnabled(false)
    }
    func showVideo() {
        self.setVideoEnabled(true)
    }
    private func setVideoEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCVideoTrack.self, isEnabled: isEnabled)
    }
}

// MARK: - Audio control
extension WebRTCClient {
    func muteAudio() {
        self.setAudioEnabled(false)
    }

    func unmuteAudio() {
        self.setAudioEnabled(true)
    }

    // Fallback to the default playing device: headphones/bluetooth/ear speaker
    func speakerOff() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try self.rtcAudioSession.overrideOutputAudioPort(.none)
            } catch {
                debugPrint("Error setting AVAudioSession category: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }

    // Force speaker
    func speakerOn() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try self.rtcAudioSession.overrideOutputAudioPort(.speaker)
                try self.rtcAudioSession.setActive(true)
            } catch {
                debugPrint("Couldn't force audio to speaker: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }

    private func setAudioEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCAudioTrack.self, isEnabled: isEnabled)
    }
}
