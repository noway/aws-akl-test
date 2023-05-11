//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI
import NIO

class EchoInputHandler : ChannelInboundHandler {
    // typealias changes to wrap out ByteBuffer in an AddressedEvelope which describes where the packages are going
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    private var numBytes = 0
    
    public init(_ expectedNumBytes: Int) {
        self.numBytes = expectedNumBytes
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        
        let data: ByteBuffer = self.unwrapInboundIn(data).data
        // convert data from ByteBuffer to Data
        let data2 = Data(data.readableBytesView)

        // split data to 1 byte message type, 8 byte Double x (Big Endian), 8 byte Double y (Big Endian)
        let messageType = data2[0]
        let xData = data2[1...8]
        let yData = data2[9...16]

        // convert x and y to Double
        let x = Double(bitPattern: UInt64(bigEndian: xData.withUnsafeBytes { $0.load(as: UInt64.self) }))
        let y = Double(bitPattern: UInt64(bigEndian: yData.withUnsafeBytes { $0.load(as: UInt64.self) }))

        print("Received: \(messageType) \(x) \(y)")
        // print(data)
        
        // let bigEndianValue: UInt64 = data.withUnsafeBytes { bytes in
        //     bytes.load(as: UInt64.self)
        // }
        // let valueAsUInt64 = UInt64(bigEndian: bigEndianValue)
        // let decodedValue = Double(bitPattern: valueAsUInt64)


        // numBytes -= self.unwrapInboundIn(data).data.readableBytes
        
        // assert(numBytes >= 0)
        
        // if numBytes == 0 {
        //     print("Received the line back from the server, closing channel")
        //     context.close(promise: nil)
        // }
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        context.close(promise: nil)
    }
}

class NetCode {
    var group: MultiThreadedEventLoopGroup? = nil
    var channel: Channel? = nil
    var remoteAddress: SocketAddress? = nil

    func connect() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = DatagramBootstrap(group: group!)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(EchoInputHandler(0))
            }

        remoteAddress = try! SocketAddress(ipAddress: "256.256.256.256", port: 65536)
        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: 0).wait()
        } catch {
            print("Failed to connect: \(error)")
            disconnect()
        }
    }

    func sendHello() {
        do {
            var data = Data()
            data.append(0x01)
            var buffer = channel!.allocator.buffer(capacity: 1)
            buffer.writeBytes(data)
            let writeData = AddressedEnvelope(remoteAddress: remoteAddress!, data: buffer)
            try channel!.writeAndFlush(writeData).wait()
        } catch {
            print("Failed to send UDP message: \(error)")
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
                    self.netCode.sendHello()
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
