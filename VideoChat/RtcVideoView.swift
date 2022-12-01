//
//  RtcVideoView.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 30/11/2022.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
struct RtcVideoView: UIViewRepresentable {
    
    let containerSize: CGSize
    let rtcViewInit: (UIView, CGSize) -> UIView
    
    init(containerSize: CGSize, rtcViewInit: @escaping (UIView, CGSize) -> UIView) {
        self.containerSize = containerSize
        self.rtcViewInit = rtcViewInit
    }

    func makeUIView(context: Context) -> UIView {
        let uiView = UIView()
        let rtcView = rtcViewInit(uiView, containerSize)
        return rtcView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
}
