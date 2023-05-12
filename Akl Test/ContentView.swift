//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI
import NIO

class PublisherClass: ObservableObject {
    @Published var squarePosition: CGSize = .zero

    func publishEvent(x: Double, y: Double) {        
        DispatchQueue.main.async {
            self.setPosition(x: x, y: y)
        }
    }

    func setPosition(x: Double, y: Double) {
        self.squarePosition.width = x
        self.squarePosition.height = y
    }
}

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
    private var publisher: PublisherClass
    
    public init(_ publisher: PublisherClass) {
        self.publisher = publisher
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let byteBuffer: ByteBuffer = self.unwrapInboundIn(data).data
        let data = Data(byteBuffer.readableBytesView)

        let messageType = data[0]
        let xData = data[1...8]
        let yData = data[9...16]
        
        let x = dataToDouble(data: xData)
        let y = dataToDouble(data: yData)

        self.publisher.publishEvent(x: x, y: y)
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

    func connect(publisher: PublisherClass) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = DatagramBootstrap(group: group!)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(EchoInputHandler(publisher))
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

class GestureStore: ObservableObject {
    var startingPoint: CGSize = .zero
}

struct ContentView: View {
    @ObservedObject var publisher = PublisherClass()
    @StateObject var gestureStore = GestureStore()

    let netCode = NetCode()

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 100, height: 100)
            .offset(self.publisher.squarePosition)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let x = self.gestureStore.startingPoint.width + gesture.translation.width
                        let y = self.gestureStore.startingPoint.height + gesture.translation.height
                        self.netCode.sendPosition(x: x, y: y)
                    }
                    .onEnded { _ in
                        self.gestureStore.startingPoint = self.publisher.squarePosition
                    }
            )
            .onAppear {
                DispatchQueue.global(qos: .background).async {
                    self.netCode.connect(publisher: publisher)
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
