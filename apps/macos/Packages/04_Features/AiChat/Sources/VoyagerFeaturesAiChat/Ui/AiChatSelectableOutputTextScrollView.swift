import AppKit

extension AiChatSelectableOutputText {
    final class IntrinsicTextScrollView: NSScrollView {
        /// 무한 폭은 NSLayoutManager 측정값을 손상시키므로 충분히 큰 유한 폭을 사용한다.
        private static let maximumMeasurementWidth: CGFloat = 1_000_000

        private weak var outputTextView: OutputTextView?
        private var allowsHorizontalOverflow = false
        private var sizingMode: SizingMode = .expandsToFillWidth
        private var naturalTextWidth: CGFloat = 0
        private var lastGeometryViewportWidth: CGFloat = 0
        private var isUpdatingGeometry = false

        init(textView: OutputTextView) {
            outputTextView = textView
            super.init(frame: .zero)
            documentView = textView
            textView.textContainer?.widthTracksTextView = false
            drawsBackground = false
            borderType = .noBorder
            hasVerticalScroller = false
            hasHorizontalScroller = false
            autohidesScrollers = true
            automaticallyAdjustsContentInsets = false
            setAccessibilityElement(false)
            setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            guard !isUpdatingGeometry, contentSize.width > 0,
                  contentSize.width != lastGeometryViewportWidth else { return }
            updateDocumentGeometry()
        }

        override var intrinsicContentSize: NSSize {
            guard let textView = outputTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else {
                return NSSize(width: NSView.noIntrinsicMetric, height: 0)
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let verticalInset = textView.textContainerInset.height * 2

            switch sizingMode {
            case .expandsToFillWidth:
                return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedHeight + verticalInset))
            case .fitsContent:
                let naturalWidth = max(naturalTextWidth, 0) + textView.textContainerInset.width * 2
                // 초기 zero viewport에서는 부모가 실제 폭을 제안하도록 intrinsic 폭을 보류한다.
                if allowsHorizontalOverflow, contentSize.width <= 0 {
                    return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedHeight + verticalInset))
                }
                let fitWidth = contentSize.width > 0 ? min(naturalWidth, contentSize.width) : naturalWidth
                return NSSize(width: fitWidth, height: ceil(usedHeight + verticalInset))
            }
        }

        func configureHorizontalOverflow(_ isEnabled: Bool) {
            allowsHorizontalOverflow = isEnabled
            hasHorizontalScroller = isEnabled
            outputTextView?.isHorizontallyResizable = isEnabled
            outputTextView?.autoresizingMask = isEnabled ? [] : [.width]
        }

        var naturalContentWidth: CGFloat {
            naturalTextWidth
        }

        func measuredHeight(at width: CGFloat) -> CGFloat {
            guard let textView = outputTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return 0 }
            let originalSize = textContainer.containerSize
            let effectiveWidth = allowsHorizontalOverflow ? Self.maximumMeasurementWidth : max(width, 1)
            textContainer.containerSize = NSSize(width: effectiveWidth, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let height = ceil(layoutManager.usedRect(for: textContainer).height + textView.textContainerInset
                .height * 2)
            textContainer.containerSize = originalSize
            layoutManager.ensureLayout(for: textContainer)
            return height
        }

        func configureSizingMode(_ mode: SizingMode) {
            sizingMode = mode
            setContentHuggingPriority(mode == .fitsContent ? .defaultHigh : .defaultLow, for: .horizontal)
            invalidateIntrinsicContentSize()
        }

        func updateDocumentGeometry() {
            guard let textView = outputTextView, !isUpdatingGeometry else { return }
            isUpdatingGeometry = true
            defer { isUpdatingGeometry = false }

            naturalTextWidth = measureNaturalTextWidth()
            let viewportWidth = contentSize.width
            lastGeometryViewportWidth = viewportWidth
            guard viewportWidth > 0 else {
                textView.textContainer?.containerSize = NSSize(
                    width: Self.maximumMeasurementWidth,
                    height: CGFloat.greatestFiniteMagnitude,
                )
                textView.frame.size.width = max(naturalTextWidth, 1)
                invalidateIntrinsicContentSize()
                return
            }

            textView.textContainer?.containerSize = NSSize(
                width: allowsHorizontalOverflow ? Self.maximumMeasurementWidth : viewportWidth,
                height: CGFloat.greatestFiniteMagnitude,
            )
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer
            {
                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)
                textView.frame.size.width = allowsHorizontalOverflow
                    ? max(viewportWidth, ceil(usedRect.width + textView.textContainerInset.width * 2))
                    : viewportWidth
                textView.frame.size.height = ceil(
                    usedRect.height + textView.textContainerInset.height * 2,
                )
            }

            if !allowsHorizontalOverflow { contentView.setBoundsOrigin(NSPoint(x: 0, y: contentView.bounds.origin.y)) }

            invalidateIntrinsicContentSize()
        }

        private func measureNaturalTextWidth() -> CGFloat {
            guard let textView = outputTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return 0 }

            let originalSize = textContainer.containerSize
            textContainer.containerSize = NSSize(
                width: Self.maximumMeasurementWidth,
                height: CGFloat.greatestFiniteMagnitude,
            )
            layoutManager.ensureLayout(for: textContainer)
            let naturalWidth = layoutManager.usedRect(for: textContainer).width
            textContainer.containerSize = originalSize
            layoutManager.ensureLayout(for: textContainer)
            return ceil(naturalWidth) + 1
        }
    }
}
