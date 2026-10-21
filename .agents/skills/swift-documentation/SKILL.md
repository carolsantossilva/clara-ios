---
name: swift-documentation
description: Write Swift API documentation with DocC, including symbol comments and catalogs. Use adr-authoring for architecture decisions.
---

# Swift documentation

Use DocC for API reference and for guides that explain how APIs work together. Keep the implementation as the source of truth.

## Workflow

1. Read the repository instructions, `Package.swift` or Xcode targets, existing `.docc` catalogs, and the declarations and call sites being documented.
2. For package or framework APIs, document public declarations with `///` comments. For app targets, document public APIs and internal symbols when their behavior or contract helps another developer use or maintain them.
3. Start each symbol comment with a precise summary. Add a discussion only for behavior that is not clear from the declaration. Use relevant DocC sections such as `Parameters`, `Returns`, `Throws`, `Important`, `Warning`, and `See Also`; omit sections that add no useful information.
4. Use a documentation catalog when readers need context beyond the symbol reference: a landing page for the module, an article for concepts or workflows, and a tutorial for a guided, step-by-step learning experience. Follow the project’s existing catalog location and naming.
5. Keep examples consistent with the actual API and make them compile when practical. Use Swift Markdown and valid DocC symbol links. Avoid duplicating reference material in articles or documenting implementation details that are not useful to the intended reader.
6. Verify symbol names, links, examples, and commands against the code. Build documentation with the project’s existing workflow; in Xcode projects, use Build Documentation or `xcodebuild docbuild` when the scheme supports it. State clearly when DocC could not be built.

## References

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [Writing symbol documentation in source files](https://developer.apple.com/documentation/xcode/writing-symbol-documentation-in-your-source-files)
- [Documenting apps, frameworks, and packages with DocC](https://developer.apple.com/documentation/xcode/documenting-apps-frameworks-and-packages)
