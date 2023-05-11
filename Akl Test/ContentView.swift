//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI
import NIO

class NetCode {
    var group: MultiThreadedEventLoopGroup? = nil
    var channel: Channel? = nil
    var remoteAddress: SocketAddress? = nil

    func connect() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = DatagramBootstrap(group: group!)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        remoteAddress = try! SocketAddress(ipAddress: "256.256.256.256", port: 65536)
        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: 0).wait()
        } catch {
            print("Failed to connect: \(error)")
            disconnect()
        }
    }

    func sendPosition(x: Double, y: Double) {
        do {
            var data = Data()
            data.append(0x02)
            withUnsafeBytes(of: x.bitPattern.bigEndian) { bytes in
                data.append(contentsOf: bytes)
            }
            withUnsafeBytes(of: y.bitPattern.bigEndian) { bytes in
                data.append(contentsOf: bytes)
            }
            var buffer = channel!.allocator.buffer(capacity: 4 * 2 + 1)
            buffer.writeBytes(data)
            let writeData = AddressedEnvelope(remoteAddress: remoteAddress!, data: buffer)
            try channel!.writeAndFlush(writeData).wait()
        } catch {
            print("Failed to send UDP message: \(error)")
            disconnect()
        }
    }

    func disconnect() {
        if let channel = channel {
            try! channel.close().wait()
        }
        if let group = group {
            try! group.syncShutdownGracefully()
        }
        group = nil
        channel = nil
        remoteAddress = nil
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
                        self.netCode.sendPosition(x: self.dragOffset.width, y: self.dragOffset.height)
                    }
                    .onEnded { _ in
                        self.savedOffset = self.dragOffset
                    }
            )
            .onAppear {
                DispatchQueue.global(qos: .background).async {
                    self.netCode.connect()
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
