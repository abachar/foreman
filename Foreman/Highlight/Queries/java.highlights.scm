; Foreman's own Java highlights (editor R12, amended 2026-10-17 — M25 25.1), written against
; IntelliJ's *Java* colour page rather than tree-sitter-java's defaults. The grammar is the
; package's; only what gets a colour changes:
;   - a type in use is plain text; only a declaration's name is a `type`;
;   - a method declaration is a `function`, a call is plain text;
;   - a field is a `property` wherever the grammar can see one (declaration, `x.field`);
;   - `this`, `super`, the primitive types and the literals `true`/`false`/`null` are keywords;
;   - an ALL_CAPS identifier is a `constant` (IntelliJ's static final).
; A parameter or a local has no capture: plain text, like IntelliJ.
; Loaded by `Language.makeConfiguration` instead of the package's `highlights.scm`.

; Comments and literals

[
  (line_comment)
  (block_comment)
] @comment

[
  (hex_integer_literal)
  (decimal_integer_literal)
  (octal_integer_literal)
  (binary_integer_literal)
  (decimal_floating_point_literal)
  (hex_floating_point_literal)
] @number

[
  (character_literal)
  (string_literal)
] @string
(escape_sequence) @string.escape

; Keywords — IntelliJ paints the literals and the primitive types with the keyword colour.

[
  (true)
  (false)
  (null_literal)
] @keyword

[
  (boolean_type)
  (integral_type)
  (floating_point_type)
  (void_type)
] @keyword

(this) @keyword
(super) @keyword

[
  "abstract"
  "assert"
  "break"
  "case"
  "catch"
  "class"
  "continue"
  "default"
  "do"
  "else"
  "enum"
  "exports"
  "extends"
  "final"
  "finally"
  "for"
  "if"
  "implements"
  "import"
  "instanceof"
  "interface"
  "module"
  "native"
  "new"
  "non-sealed"
  "open"
  "opens"
  "package"
  "permits"
  "private"
  "protected"
  "provides"
  "public"
  "record"
  "requires"
  "return"
  "sealed"
  "static"
  "strictfp"
  "switch"
  "synchronized"
  "throw"
  "throws"
  "to"
  "transient"
  "transitive"
  "try"
  "uses"
  "volatile"
  "when"
  "while"
  "with"
  "yield"
] @keyword

; Annotations — the `@` included, as IntelliJ colours it.

(annotation
  "@" @attribute
  name: (_) @attribute)
(marker_annotation
  "@" @attribute
  name: (_) @attribute)

; Constants — an ALL_CAPS identifier, declared or used (IntelliJ: a static final field).

((identifier) @constant
 (#match? @constant "^_*[A-Z][A-Z\\d_]+$"))

(enum_constant
  name: (identifier) @constant)

; Fields — purple where the grammar can tell a field from a local.

(field_declaration
  declarator: (variable_declarator
    name: (identifier) @property))

(field_access
  field: (identifier) @property)

; Methods — the declaration is coloured, the call is not.

(method_declaration
  name: (identifier) @function.method)

(constructor_declaration
  name: (identifier) @function.method)

(compact_constructor_declaration
  name: (identifier) @function.method)

; Types — only the declared name.

(class_declaration
  name: (identifier) @type)
(interface_declaration
  name: (identifier) @type)
(enum_declaration
  name: (identifier) @type)
(record_declaration
  name: (identifier) @type)
(annotation_type_declaration
  name: (identifier) @type)
