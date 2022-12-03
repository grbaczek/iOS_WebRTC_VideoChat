//
//  ContentView.swift
//  VideoChat
//
//  Created by Grzegorz Baczek on 14/11/2022.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                NavigationLink("Create chat room") {
                    CreateChatRoomView()
                        .navigationTitle("Create chat room")
                }
                .padding()
                NavigationLink("Join chat room") {
                    JoinChatRoomView()
                        .navigationTitle("Join chat room")
                }
                .padding()
                Spacer()
            }
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
