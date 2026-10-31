# REFERENCE_SYNTAX_TOP

Basic Markdown syntax for rendering checks.

## Emphasis

Plain, **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and `inline code` in one sentence that is
long enough to wrap when the preview is narrow, so wrapping and inline styles are exercised together.

## Lists

- First bullet
  - Nested bullet
    - Third level
- Second bullet

1. First
2. Second
   1. Nested ordered

- [ ] Open task
- [x] Done task

## Links and quotes

A [link](https://example.com), an autolink <https://example.com/auto>, and an image ![alt](image.png).

> A blockquote with **bold** text.
>
> > A nested quote.

---

## Code

```python
def greet(name):
    return f"hello {name}"  # comment
```

```bash
echo "hello" | tr a-z A-Z
```

    indented code block

## Syntax Highlighting

```rust
fn main() { println!("REFERENCE_SYNTAX_CODE"); }
```

REFERENCE_SYNTAX_BOTTOM
