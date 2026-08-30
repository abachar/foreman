import CoreGraphics

/// design R6: the preview's spacing, derived from the reading size (2026-08-30).
///
/// Every number GitHub uses in `github-markdown-css` is a multiple of its 16 px base
/// (`--base-size-16`, `-24`, `-8`, `-4`), so they are kept as multiples of `readingFontSize`
/// rather than copied as constants: a reader who raises the reading size gets the whole layout
/// with it, and no metric is written inline in a view (`coding-rules`, UI).
nonisolated struct MarkdownMetrics: Equatable {
    let base: CGFloat

    init(readingFontSize: CGFloat) {
        base = readingFontSize
    }

    /// Between two blocks (GitHub: `margin-bottom: 16` on p, ul, ol, table, pre, blockquote).
    var blockSpacing: CGFloat { base }

    /// Above a heading, on top of `blockSpacing`.
    ///
    /// GitHub's `margin-top: 24` is the total; the stack already provides `blockSpacing`, so a
    /// heading only adds the difference.
    var headingTop: CGFloat { (base * 1.5 - blockSpacing).rounded() }

    /// Between an `h1`/`h2` and the rule under it (GitHub: `padding-bottom: .3em` of the heading's
    /// own size, so it grows with the heading).
    func headingRuleGap(size: CGFloat) -> CGFloat {
        (size * 0.3).rounded()
    }

    /// The width of the marker column; with `markerGap` the content lands at `2 × base`, which is
    /// GitHub's `padding-left: 2em` on a list.
    var markerColumn: CGFloat { (base * 1.5).rounded() }
    var markerGap: CGFloat { (base * 0.5).rounded() }
    var listIndent: CGFloat { markerColumn + markerGap }

    /// Between two items of one list (GitHub: `li + li { margin-top: .25em }`).
    var itemSpacing: CGFloat { (base * 0.25).rounded() }

    /// Between the blocks of one item (GitHub: `li > p { margin-top: 16 }`).
    var itemBlockSpacing: CGFloat { base }

    /// Inside a code block (GitHub: `padding: 16`).
    var codePadding: CGFloat { base }

    /// From a quote's bar to its text (GitHub: `padding: 0 1em`).
    var quoteGap: CGFloat { base }

    /// The quote's bar.
    ///
    /// Not GitHub's `.25em`: the bar stays as it is (author's call 2026-08-30).
    var quoteBar: CGFloat { 3 }

    /// Inside a table cell (GitHub: `padding: 6px 13px`).
    var cellPadding: (vertical: CGFloat, horizontal: CGFloat) {
        ((base * 0.375).rounded(), (base * 0.8125).rounded())
    }

    /// GitHub keeps 6 px whatever the size, and so do we.
    var codeRadius: CGFloat { 6 }
}
