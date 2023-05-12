//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI
import NIO

class SquareState: ObservableObject {
    @Published var squarePosition: CGSize = .zero

    func setPosition(x: Double, y: Double) {
        self.squarePosition.width = x
        self.squarePosition.height = y
    }
}

class GestureState: ObservableObject {
    var startingPoint: CGSize = .zero
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

class IncomingDatagramHandler : ChannelInboundHandler {
    // typealias changes to wrap out ByteBuffer in an AddressedEnvelope which describes where the packages are going
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    private var squareState: SquareState
    
    public init(_ squareState: SquareState) {
        self.squareState = squareState
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let byteBuffer: ByteBuffer = self.unwrapInboundIn(data).data
        let data = Data(byteBuffer.readableBytesView)

        _ = data[0]
        let xData = data[1...8]
        let yData = data[9...16]
        
        let x = dataToDouble(data: xData)
        let y = dataToDouble(data: yData)

        DispatchQueue.main.async {
            self.squareState.setPosition(x: x, y: y)
        }
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

    func connect(squareState: SquareState) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = DatagramBootstrap(group: group!)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(IncomingDatagramHandler(squareState))
            }

        let remoteAddr = Bundle.main.object(forInfoDictionaryKey: "RemoteAddr") as? String ?? ""
        let remotePortStr = Bundle.main.object(forInfoDictionaryKey: "RemotePort") as? String ?? "0"
        let remotePort = Int(remotePortStr) ?? 0
        remoteAddress = try! SocketAddress(ipAddress: remoteAddr, port: remotePort)
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
    @ObservedObject var squareState = SquareState()
    @StateObject var gestureState = GestureState()

    let netCode = NetCode()

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 100, height: 100)
            .offset(self.squareState.squarePosition)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let x = self.gestureState.startingPoint.width + gesture.translation.width
                        let y = self.gestureState.startingPoint.height + gesture.translation.height
                        self.netCode.sendPosition(x: x, y: y)
                    }
                    .onEnded { _ in
                        self.gestureState.startingPoint = self.squareState.squarePosition
                    }
            )
            .onAppear {
                DispatchQueue.global(qos: .background).async {
                    self.netCode.connect(squareState: squareState)
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
