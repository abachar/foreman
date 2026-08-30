# Markdown reference document

The one document rendered on both sides for [the comparison](../01-markdown-vs-github.md) (M16 16.3).
It holds every construct `editor` R14 claims to render, and nothing else: what is not here was not
compared. Foreman renders this file directly (`cmd+shift+v` shows the preview); the GitHub side is
this same text as HTML under `github-markdown.css`, in a 1012 px column. The captures are next to
this file.

This paragraph exists to judge the body: its size, its leading, and the space between two blocks.
A second sentence gives the line enough length to wrap at a normal window width, which is what the
maximum reading width is about.

## Heading 2, with a rule under it on GitHub

A paragraph under an `h2`, to see how much air the heading leaves above and below it.

### Heading 3

#### Heading 4

##### Heading 5

###### Heading 6

Inline runs, all in one line: *emphasis*, **strong**, ***both***, ~~struck through~~,
`inline code`, a [link to an external page](https://github.com), a
[link to a file of the workspace](../00-study.md), and a bare URL <https://example.com>.

A very long line with no break in it, to see what each side does when nothing can wrap: this
sentence keeps going and going without a single hard return so that the renderer has to decide
between wrapping it at the reading width, wrapping it at the window width, or letting it run under
a horizontal scroll bar, which is exactly the difference worth writing down.

## Lists

- A first item.
- A second item, long enough to wrap onto a second line so the hanging indent of the marker can be
  judged against the text above it.
- A third item with nested children:
  - A nested item.
  - Another nested item, itself with children:
    - A third level.
- A last item.

1. An ordered item.
2. A second one.
   1. A nested ordered item.
   2. Another one.
3. A third one.

A paragraph, so the next list is a new one and its `start` is really exercised.

5. An ordered list that does not start at one.
6. Its second item.

- [ ] An unchecked task.
- [x] A checked task.
- [ ] A task long enough to wrap, so the checkbox alignment against a second line shows.

A paragraph after the lists, to see the space a list leaves behind it.

## Quotes

> A quote of one paragraph.

> A quote of two paragraphs, the first one long enough to wrap so its left bar can be measured
> against the text it holds.
>
> The second paragraph of the same quote.
>
> > A quote inside a quote.

## Code

Inline `code` inside a sentence, next to a longer run of `NSTextView.textContainerInset` so the
padding and the background of an inline run can be judged at two lengths.

```swift
/// A code block with a language the highlighter knows.
struct Scratch {
    static let relativeFolder = ".foreman/scratches"

    static func nextTitle(taken: Set<String>) -> String {
        guard taken.contains("Untitled") else { return "Untitled" }
        return "Untitled 2"
    }
}
```

```json
{ "editor": { "insertFinalNewline": true }, "theme": { "readingFontSize": 16 } }
```

```
A code block with no language at all, which must still get its background, its padding and its
radius — and a line long enough to need a horizontal scroll rather than a wrap.
```

## Tables

| Construct | Foreman | GitHub | Gap |
|---|---|---|---|
| Body | 16 pt | 16 px | none |
| A longer cell | a value that wraps or does not | another value | to be seen |
| Third row | value | value | value |

## A rule, then an image

---

![The reference image](image.png)

A paragraph after the image, the last block of the document.
