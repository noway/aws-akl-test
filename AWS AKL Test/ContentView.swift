//
//  ContentView.swift
//  AWS AKL Test
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

func dataToFloat(data: Data) -> Float {
    let bigEndianValue: UInt32 = data.withUnsafeBytes { bytes -> UInt32 in
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { valueBytes in
            bytes.copyBytes(to: valueBytes)
        }
        return value
    }
    let valueAsUInt64 = UInt32(bigEndian: bigEndianValue)
    return Float(bitPattern: valueAsUInt64)
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
        let xData = data[1...4]
        let yData = data[5...8]
        
        let x = dataToFloat(data: xData)
        let y = dataToFloat(data: yData)

        DispatchQueue.main.async {
            self.squareState.setPosition(x: Double(x), y: Double(y))
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
    var squareState: SquareState? = nil

    func connect(squareState: SquareState) {
        self.squareState = squareState
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = DatagramBootstrap(group: group!)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(IncomingDatagramHandler(squareState))
            }

        let remoteAddr = Bundle.main.object(forInfoDictionaryKey: "RemoteAddr") as? String ?? ""
        let remotePortStr = Bundle.main.object(forInfoDictionaryKey: "RemotePort") as? String ?? "0"
        let remotePort = Int(remotePortStr) ?? 0
        
        do {
            remoteAddress = try SocketAddress(ipAddress: remoteAddr, port: remotePort)
            channel = try bootstrap.bind(host: "0.0.0.0", port: 0).wait()
        } catch {
            print("Failed to connect: \(error)")
            disconnect()
        }
    }

    func reconnect() {
        disconnect()
        connect(squareState: squareState!)
    }

    func sendHello() {
        if channel == nil {
            reconnect()
        }

        do {
            var data = Data()
            data.append(0x01)
            var buffer = channel!.allocator.buffer(capacity: 1)
            buffer.writeBytes(data)
            let writeData = AddressedEnvelope(remoteAddress: remoteAddress!, data: buffer)
            try channel!.writeAndFlush(writeData).wait()
        } catch {
            print("Failed to sendHello: \(error)")
            disconnect()
        }
    }

    func sendPosition(x: Float, y: Float) {
        if channel == nil {
            reconnect()
        }

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
            print("Failed to sendPosition: \(error)")
            disconnect()
        }
    }

    func disconnect() {
        do {
            if let channel = channel {
                if channel.isActive {
                    try channel.close().wait()
                }
            }
            if let group = group {
                try group.syncShutdownGracefully()
            }
            group = nil
            channel = nil
            remoteAddress = nil
        } catch {
            print("Failed to disconnect: \(error)")
        }
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
                        DispatchQueue.global(qos: .background).async {
                            let x = self.gestureState.startingPoint.width + gesture.translation.width
                            let y = self.gestureState.startingPoint.height + gesture.translation.height
                            self.netCode.sendPosition(x: Float(x), y: Float(y))
                        }
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
