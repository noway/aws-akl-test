//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI
import NIO

func dataToDouble(data: Data) -> Double {
    let bigEndianValue: UInt64 = data.withUnsafeBytes { bytes -> UInt64 in
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { valueBytes in
            bytes.copyBytes(to: valueBytes)
        }
        return value
    }
    let valueAsUInt64 = UInt64(bigEndian: bigEndianValue)
    return Double(bitPattern: valueAsUInt64)
}

class EchoInputHandler : ChannelInboundHandler {
    // typealias changes to wrap out ByteBuffer in an AddressedEvelope which describes where the packages are going
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    private var numBytes = 0
    
    public init(_ expectedNumBytes: Int) {
        self.numBytes = expectedNumBytes
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let byteBuffer: ByteBuffer = self.unwrapInboundIn(data).data
        let data = Data(byteBuffer.readableBytesView)

        let messageType = data[0]
        let xData = data[1...8]
        let yData = data[9...16]
        
        let x = dataToDouble(data: xData)
        let y = dataToDouble(data: yData)

        print("Received: \(messageType) \(x) \(y)")        
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
