//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI
import NIO

class NetCode {
    func sendPing() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        defer {
            try! group.syncShutdownGracefully()
        }
        let message = "ping"
        let remoteAddress = try! SocketAddress(ipAddress: "256.256.256.256", port: 65536)
        do {
            let channel = try bootstrap.bind(host: "0.0.0.0", port: 0).wait()
            defer {
                try! channel.close().wait()
            }

            var buffer = channel.allocator.buffer(capacity: message.utf8.count)
            buffer.writeString(message)

            let writeData = AddressedEnvelope(remoteAddress: remoteAddress, data: buffer)
            try channel.writeAndFlush(writeData).wait()
        } catch {
            print("Failed to send UDP message: \(error)")
        }
    }
}


struct ContentView: View {
    @State private var savedOffset = CGSize.zero
    @State private var dragOffset = CGSize.zero
    let netCode = NetCode()

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 100, height: 100)
            .offset(dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        self.dragOffset.width = self.savedOffset.width + gesture.translation.width
                        self.dragOffset.height = self.savedOffset.height + gesture.translation.height
                    }
                    .onEnded { _ in
                        self.savedOffset = self.dragOffset
                    }
            )
            .onAppear {
                DispatchQueue.global(qos: .background).async {
                    self.netCode.sendPing()
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
