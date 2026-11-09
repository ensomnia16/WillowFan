import AppKit

/// Keeps the live status comfortably inset from the standalone window edge.
final class ToolbarStatusView: NSView {
    private let pill: StatusPill

    init(pill: StatusPill) {
        self.pill = pill
        super.init(frame: .zero)
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        frame.size = intrinsicContentSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: pill.intrinsicContentSize.width + 28, height: 34)
    }
}
