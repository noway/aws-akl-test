//
//  ContentView.swift
//  Akl Test
//
//  Created by Ilia Sidorenko on 12/05/23.
//

import SwiftUI

struct ContentView: View {
    @State private var savedOffset = CGSize.zero
    @State private var dragOffset = CGSize.zero

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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
