//
//  StretchyModifier.swift
//  iWatch
//
//  Created by Tyler Keegan on 8/21/25.
//

import Foundation
import SwiftUI

// MARK: - If Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Stretchy Modifier
extension View {
    func stretchy() -> some View {
        visualEffect { effect, geometry in
            let currentHeight = geometry.size.height
            let scrollOffset = geometry.frame(in: .scrollView).minY
            let positiveOffset = max(0, scrollOffset)

            let newHeight = currentHeight + positiveOffset
            let scaleFactor = newHeight / currentHeight

            return effect.scaleEffect(
                x: scaleFactor, y: scaleFactor,
                anchor: .bottom
            )
        }
    }
}

// MARK: - Number of Lines Modifier
extension View {
  /// Counts the number of lines it takes to draw a string, including word wrapping.
  /// This doesn't count the number of newline characters in a string.
  func onNumberOfLinesChange(_ onChange: @escaping (Int) -> Void) -> some View {
    modifier(OnNumberOfLinesChangeViewModifier(onChange: onChange))
  }
}

struct OnNumberOfLinesChangeViewModifier: ViewModifier {
  let onChange: (Int) -> Void

  func body(content: Content) -> some View {
    content.onPreferenceChange(Text.LayoutKey.self) { textLayout in
      var count = 0

      for layout in textLayout {
        count += layout.layout.count
      }

      if count != numberOfLines {
        onChange(count)
      }

      numberOfLines = count
    }
  }

  @State private var numberOfLines: Int = 0
}
