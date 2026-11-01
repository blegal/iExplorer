import AppKit

/// Coloration syntaxique légère par expressions régulières (sans dépendance).
/// Le langage se déduit du nom du fichier (Makefile, CMakeLists.txt, Dockerfile…) puis de son extension.
enum SyntaxHighlighter {
    enum Language {
        case swift, cFamily, python, javascript, java, go, rust, shell, json, tex, bibtex, markdown, plain
        case make, cmake, vhdl, verilog, tcl, yaml, ini, xml, css, sql, lua, ruby, perl, php, r, julia
        case dockerfile, assembly, fortran, haskell, diff
        case typst, matlab, spice, linker, fpga, gnuplot, scala, kotlin, csharp, rst, asciidoc, org, subtitles
        case powershell, batch, awk, sed, m4, vim, hcl, nix, meson, ninja, just, protobuf, graphql, template
        case elixir, erlang, ocaml, fsharp, clojure, lisp, zig, nim, pascal, ada, mathematica

        /// Nom affiché dans la barre d'état de l'éditeur.
        var title: String {
            switch self {
            case .swift: "Swift"
            case .cFamily: "C / C++ / Objective-C"
            case .python: "Python"
            case .javascript: "JavaScript / TypeScript"
            case .java: "Java / Kotlin / C#"
            case .go: "Go"
            case .rust: "Rust"
            case .shell: "Shell"
            case .json: "JSON"
            case .tex: "LaTeX"
            case .bibtex: "BibTeX"
            case .markdown: "Markdown"
            case .plain: L("Texte")
            case .make: "Makefile"
            case .cmake: "CMake"
            case .vhdl: "VHDL"
            case .verilog: "Verilog / SystemVerilog"
            case .tcl: "Tcl"
            case .yaml: "YAML"
            case .ini: L("Configuration")
            case .xml: "XML / HTML"
            case .css: "CSS"
            case .sql: "SQL"
            case .lua: "Lua"
            case .ruby: "Ruby"
            case .perl: "Perl"
            case .php: "PHP"
            case .r: "R"
            case .julia: "Julia"
            case .dockerfile: "Dockerfile"
            case .assembly: L("Assembleur")
            case .fortran: "Fortran"
            case .haskell: "Haskell"
            case .diff: "Diff"
            case .typst: "Typst"
            case .matlab: "Matlab / Octave"
            case .spice: "SPICE"
            case .linker: L("Script d’édition de liens")
            case .fpga: L("Contraintes FPGA")
            case .gnuplot: "Gnuplot"
            case .scala: "Scala / Chisel"
            case .kotlin: "Kotlin"
            case .csharp: "C#"
            case .rst: "reStructuredText"
            case .asciidoc: "AsciiDoc"
            case .org: "Org"
            case .subtitles: L("Sous-titres")
            case .powershell: "PowerShell"
            case .batch: L("Batch Windows")
            case .awk: "Awk"
            case .sed: "Sed"
            case .m4: "M4 / Autoconf"
            case .vim: "Vim script"
            case .hcl: "Terraform / HCL"
            case .nix: "Nix"
            case .meson: "Meson"
            case .ninja: "Ninja"
            case .just: "Justfile"
            case .protobuf: "Protocol Buffers"
            case .graphql: "GraphQL"
            case .template: L("Gabarit (Jinja, Handlebars…)")
            case .elixir: "Elixir"
            case .erlang: "Erlang"
            case .ocaml: "OCaml"
            case .fsharp: "F#"
            case .clojure: "Clojure"
            case .lisp: "Lisp / Scheme"
            case .zig: "Zig"
            case .nim: "Nim"
            case .pascal: "Pascal / Delphi"
            case .ada: "Ada"
            case .mathematica: "Mathematica"
            }
        }
    }

    static func language(for url: URL) -> Language? {
        let name = url.lastPathComponent
        switch name.lowercased() {
        case "makefile", "gnumakefile", "bsdmakefile", "kbuild": return .make
        case "cmakelists.txt": return .cmake
        case "dockerfile", "containerfile": return .dockerfile
        case "rakefile", "gemfile", "podfile", "fastfile", "brewfile", "vagrantfile": return .ruby
        case "sconstruct", "sconscript", "wscript", "snakefile": return .python
        case ".bashrc", ".bash_profile", ".zshrc", ".zprofile", ".zshenv", ".profile", ".envrc": return .shell
        case ".gitignore", ".gitattributes", ".gitmodules", ".gitconfig", ".dockerignore", ".editorconfig", ".npmrc", ".env", "pipfile": return .ini
        case "build", "build.bazel", "workspace", "workspace.bazel", "module.bazel": return .python
        case "meson.build", "meson_options.txt", "meson.options": return .meson
        case "justfile", ".justfile": return .just
        case "configure.ac", "configure.in": return .m4
        case ".vimrc", "_vimrc", ".gvimrc", ".exrc": return .vim
        case ".babelrc", ".eslintrc", ".prettierrc", ".swcrc": return .json
        case "jenkinsfile": return .java
        default: break
        }
        if name.lowercased().hasPrefix("dockerfile.") { return .dockerfile }
        if name.lowercased().hasPrefix("makefile.") { return .make }
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "m": return isObjectiveC(url) ? .cFamily : .matlab
        case "c", "h", "cpp", "hpp", "cc", "hh", "cxx", "hxx", "inl", "ipp", "mm", "cu", "cuh", "cl", "ino", "glsl", "vert", "frag", "metal", "hlsl",
             "l", "y", "ll", "yy", "lex": return .cFamily
        case "py", "pyw", "pyi": return .python
        case "js", "mjs", "cjs", "ts", "tsx", "jsx", "mts", "cts": return .javascript
        case "java", "groovy", "gradle", "dart": return .java
        case "kt", "kts": return .kotlin
        case "scala", "sc": return .scala
        case "cs", "csx": return .csharp
        case "go": return .go
        case "rs": return .rust
        case "sh", "bash", "zsh", "fish", "ksh", "command": return .shell
        case "json", "geojson", "jsonc", "json5", "jsonl", "ndjson", "ipynb", "webmanifest", "har": return .json
        case "tex", "sty", "cls", "ltx", "dtx": return .tex
        case "bib": return .bibtex
        case "md", "markdown", "mdown", "mkd", "mdx", "rmd", "qmd": return .markdown
        case "mk", "mak", "make": return .make
        case "cmake": return .cmake
        case "vhd", "vhdl", "vho", "vht": return .vhdl
        case "v", "vh", "sv", "svh", "svi": return .verilog
        case "tcl", "xdc", "sdc", "do", "tk", "qsf", "upf": return .tcl
        case "yaml", "yml": return .yaml
        case "toml", "ini", "cfg", "conf", "properties", "desktop", "service", "env": return .ini
        case "xml", "html", "htm", "xhtml", "svg", "plist", "xsd", "xsl", "xslt", "storyboard", "xib", "vue", "ui", "qrc", "svelte", "astro": return .xml
        case "css", "scss", "sass", "less": return .css
        case "sql": return .sql
        case "lua": return .lua
        case "rb", "rake", "gemspec": return .ruby
        case "pl", "pm", "t": return .perl
        case "php": return .php
        case "r": return .r
        case "jl": return .julia
        case "s", "asm", "nasm": return .assembly
        case "f", "for", "f77", "f90", "f95", "f03", "f08": return .fortran
        case "hs", "lhs": return .haskell
        case "diff", "patch": return .diff
        case "typ": return .typst
        case "sp", "cir", "spice", "ckt", "net", "spi": return .spice
        case "ld", "lds": return .linker
        case "ucf", "pcf", "lpf", "pdc": return .fpga
        case "gp", "gnuplot", "plt", "gpi": return .gnuplot
        case "rst", "rest": return .rst
        case "adoc", "asciidoc": return .asciidoc
        case "org": return .org
        case "srt", "vtt": return .subtitles
        case "ps1", "psm1", "psd1": return .powershell
        case "bat", "cmd": return .batch
        case "awk": return .awk
        case "sed": return .sed
        case "m4", "ac": return .m4
        case "vim": return .vim
        case "tf", "tfvars", "hcl", "nomad": return .hcl
        case "nix": return .nix
        case "ninja": return .ninja
        case "just": return .just
        case "bzl", "star": return .python
        case "proto": return .protobuf
        case "graphql", "gql", "graphqls": return .graphql
        case "j2", "jinja", "jinja2", "hbs", "handlebars", "mustache", "njk", "liquid", "twig": return .template
        case "ex", "exs": return .elixir
        case "erl", "hrl": return .erlang
        case "ml", "mli": return .ocaml
        case "fs", "fsi", "fsx": return .fsharp
        case "clj", "cljs", "cljc", "edn": return .clojure
        case "lisp", "lsp", "el", "scm", "ss", "rkt", "sld": return .lisp
        case "zig", "zon": return .zig
        case "nim", "nims", "nimble": return .nim
        case "pas", "pp", "dpr", "lpr": return .pascal
        case "adb", "ads", "ada": return .ada
        case "wl", "wls": return .mathematica
        case "txt", "log", "csv", "tsv": return .plain
        default: return nil
        }
    }

    private static var objectiveCCache: [String: Bool] = [:]

    /// `.m` : Objective-C si le début du fichier en a les marques (#import, @interface…), sinon Matlab.
    private static func isObjectiveC(_ url: URL) -> Bool {
        if let known = objectiveCCache[url.path] { return known }
        let head = (try? FileHandle(forReadingFrom: url)).flatMap { handle in
            defer { try? handle.close() }
            return try? handle.read(upToCount: 8000)
        }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let result = head.range(of: #"(?m)^\s*(?:#\s*(?:import|include|define|if)|@(?:interface|implementation|protocol|end|property|class))\b"#,
                                options: .regularExpression) != nil
        objectiveCCache[url.path] = result
        return result
    }

    /// Mots-clés, commentaires, chaînes et motifs propres à un langage.
    private struct Grammar {
        var keywords: [String] = []
        var caseInsensitive = false
        /// Débuts de commentaire de fin de ligne (#, //, --, ;, !…).
        var lineComments: [String] = []
        var blockComment: (open: String, close: String)?
        /// Motif des chaînes de caractères.
        var strings = #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#
        /// Motifs supplémentaires et leur couleur, appliqués avant chaînes et commentaires.
        var extra: [(pattern: String, role: Role)] = []
    }

    private enum Role { case keyword, string, comment, number, command, added, removed }

    private static func grammar(for language: Language) -> Grammar? {
        switch language {
        case .swift:
            Grammar(keywords: ["func", "let", "var", "if", "else", "guard", "return", "for", "in", "while", "repeat", "switch", "case", "default",
                               "class", "struct", "enum", "protocol", "extension", "import", "private", "fileprivate", "public", "internal", "open",
                               "static", "self", "Self", "super", "init", "deinit", "try", "catch", "throw", "throws", "rethrows", "async", "await",
                               "nil", "true", "false", "override", "final", "where", "some", "any", "defer", "lazy", "weak", "unowned", "mutating",
                               "inout", "typealias", "associatedtype", "break", "continue", "fallthrough", "is", "as", "do"],
                    lineComments: ["//"], blockComment: ("/*", "*/"), strings: #""(?:\\.|[^"\\\n])*""#,
                    extra: [(#"@\w+"#, .command), (#"#\w+"#, .command)])
        case .cFamily:
            Grammar(keywords: ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "const", "static", "struct", "union",
                               "enum", "typedef", "if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue",
                               "sizeof", "class", "public", "private", "protected", "template", "typename", "namespace", "using", "new", "delete",
                               "true", "false", "nullptr", "NULL", "auto", "virtual", "inline", "extern", "volatile", "register", "bool",
                               "constexpr", "override", "final", "noexcept", "explicit", "friend", "operator", "this", "throw", "try", "catch",
                               "static_cast", "dynamic_cast", "reinterpret_cast", "const_cast", "size_t", "uint8_t", "uint16_t", "uint32_t",
                               "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "@interface", "@implementation", "@end", "@property", "self",
                               "__global__", "__device__", "__host__", "__shared__", "kernel", "uniform", "in", "out"],
                    lineComments: ["//"], blockComment: ("/*", "*/"),
                    extra: [(#"(?m)^\s*#\s*\w+"#, .command), (#"\b0[xX][0-9a-fA-F]+[uUlL]*\b"#, .number),
                            (#"(?m)^%(?:%|\{|\}|\w+)"#, .command)])
        case .python:
            Grammar(keywords: ["def", "class", "if", "elif", "else", "for", "while", "in", "return", "import", "from", "as", "with", "try", "except",
                               "finally", "raise", "lambda", "yield", "pass", "break", "continue", "None", "True", "False", "and", "or", "not",
                               "is", "self", "async", "await", "global", "nonlocal", "match", "case", "del", "assert"],
                    lineComments: ["#"],
                    strings: #"(?s:""".*?"""|'''.*?''')|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#,
                    extra: [(#"(?m)^\s*@[\w.]+"#, .command)])
        case .javascript:
            Grammar(keywords: ["function", "const", "let", "var", "if", "else", "for", "while", "do", "return", "class", "extends", "import", "export",
                               "from", "default", "new", "this", "super", "async", "await", "try", "catch", "finally", "throw", "null", "undefined",
                               "true", "false", "interface", "type", "enum", "of", "in", "instanceof", "typeof", "switch", "case", "break",
                               "continue", "yield", "static", "public", "private", "protected", "readonly", "implements", "as", "void"],
                    lineComments: ["//"], blockComment: ("/*", "*/"),
                    strings: #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"#)
        case .java:
            Grammar(keywords: ["public", "private", "protected", "internal", "class", "interface", "object", "extends", "implements", "static",
                               "final", "abstract", "void", "int", "long", "double", "float", "boolean", "char", "byte", "short", "if", "else",
                               "for", "while", "do", "return", "new", "this", "super", "null", "true", "false", "try", "catch", "finally", "throw",
                               "throws", "import", "package", "val", "var", "fun", "override", "when", "is", "in", "as", "data", "sealed",
                               "companion", "suspend", "namespace", "using", "string", "def", "switch", "case", "default", "break", "continue",
                               "async", "await", "record", "enum"],
                    lineComments: ["//"], blockComment: ("/*", "*/"), extra: [(#"@\w+"#, .command)])
        case .go:
            Grammar(keywords: ["func", "package", "import", "var", "const", "type", "struct", "interface", "if", "else", "for", "range", "return",
                               "go", "defer", "chan", "map", "select", "switch", "case", "default", "nil", "true", "false", "break", "continue",
                               "fallthrough", "goto", "string", "int", "bool", "error", "byte", "rune", "float64", "any"],
                    lineComments: ["//"], blockComment: ("/*", "*/"),
                    strings: #""(?:\\.|[^"\\\n])*"|`[^`]*`|'(?:\\.|[^'\\\n])'"#)
        case .rust:
            Grammar(keywords: ["fn", "let", "mut", "if", "else", "match", "for", "in", "while", "loop", "return", "struct", "enum", "impl", "trait",
                               "pub", "use", "mod", "crate", "self", "Self", "super", "true", "false", "async", "await", "move", "ref", "where",
                               "unsafe", "const", "static", "type", "dyn", "as", "break", "continue", "extern"],
                    lineComments: ["//"], blockComment: ("/*", "*/"), strings: #""(?:\\.|[^"\\])*""#,
                    extra: [(#"\b\w+!"#, .command), (#"#!?\[[^\]]*\]"#, .command), (#"'\w+\b(?!')"#, .number)])
        case .shell:
            Grammar(keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "function",
                               "return", "export", "local", "readonly", "echo", "printf", "set", "unset", "source", "exit", "shift", "cd", "test"],
                    lineComments: ["#"], extra: [(#"\$\{[^}]*\}|\$[\w@#?$!*-]"#, .command)])
        case .make:
            Grammar(keywords: ["ifeq", "ifneq", "ifdef", "ifndef", "else", "endif", "include", "-include", "sinclude", "define", "endef",
                               "export", "unexport", "override", "vpath", ".PHONY", ".SUFFIXES", ".DEFAULT", ".PRECIOUS", ".INTERMEDIATE",
                               ".SECONDARY", ".DELETE_ON_ERROR", ".SILENT", ".ONESHELL"],
                    lineComments: ["#"], strings: #"(?!)"#,
                    extra: [(#"(?m)^[^\s#=:][^#=:]*?(?=\s*::?(?!=))"#, .command),
                            (#"(?m)^\s*[A-Za-z_][\w.-]*(?=\s*(?:[:+?!]|::)?=)"#, .keyword),
                            (#"\$[({][^)}]*[)}]|\$[@<^+?*%|]"#, .number)])
        case .cmake:
            Grammar(keywords: ["PUBLIC", "PRIVATE", "INTERFACE", "REQUIRED", "COMPONENTS", "STATUS", "WARNING", "FATAL_ERROR", "SEND_ERROR",
                               "ON", "OFF", "TRUE", "FALSE", "YES", "NO", "AND", "OR", "NOT", "DEFINED", "VERSION", "CACHE", "STRING", "BOOL",
                               "PATH", "FILEPATH", "INTERNAL", "FORCE", "EQUAL", "LESS", "GREATER", "STREQUAL", "MATCHES", "EXISTS", "TARGET",
                               "SHARED", "STATIC", "MODULE", "OBJECT", "IMPORTED", "ALIAS", "LANGUAGES", "DESTINATION", "FILES", "DIRECTORY",
                               "PROPERTIES", "APPEND", "PARENT_SCOPE", "IN", "LISTS", "ITEMS", "RANGE", "CONFIG", "QUIET", "NAMES", "HINTS"],
                    lineComments: ["#"], blockComment: ("#[[", "]]"), strings: #""(?:\\.|[^"\\])*""#,
                    extra: [(#"(?m)^\s*\w+(?=\s*\()"#, .command), (#"\$\{[^}]*\}|\$ENV\{[^}]*\}|\$<[^>]*>"#, .number)])
        case .vhdl:
            Grammar(keywords: ["library", "use", "entity", "is", "port", "generic", "map", "end", "architecture", "of", "begin", "signal", "variable",
                               "constant", "type", "subtype", "array", "record", "range", "to", "downto", "process", "if", "then", "else", "elsif",
                               "case", "when", "others", "for", "loop", "while", "generate", "component", "function", "procedure", "return",
                               "package", "body", "in", "out", "inout", "buffer", "and", "or", "not", "nand", "nor", "xor", "xnor", "sll", "srl",
                               "sla", "sra", "rol", "ror", "mod", "rem", "abs", "after", "wait", "until", "on", "null", "open", "all", "with",
                               "select", "configuration", "attribute", "alias", "file", "access", "new", "assert", "report", "severity",
                               "rising_edge", "falling_edge", "std_logic", "std_logic_vector", "std_ulogic", "std_ulogic_vector", "unsigned",
                               "signed", "integer", "natural", "positive", "boolean", "bit", "bit_vector", "string", "real", "time", "ieee",
                               "work", "std", "true", "false", "block", "impure", "pure", "shared", "exit", "next", "label", "units", "context"],
                    caseInsensitive: true, lineComments: ["--"], blockComment: ("/*", "*/"),
                    strings: #""(?:""|[^"\n])*"|'[^'\n]'(?!\w)"#,
                    extra: [(#"(?i)\b[bxod]"[0-9a-f_]+""#, .number), (#"'\w+"#, .command)])
        case .verilog:
            Grammar(keywords: ["module", "endmodule", "input", "output", "inout", "wire", "reg", "logic", "bit", "byte", "int", "integer", "real",
                               "parameter", "localparam", "assign", "always", "always_ff", "always_comb", "always_latch", "initial", "begin", "end",
                               "if", "else", "case", "casez", "casex", "endcase", "default", "for", "while", "repeat", "forever", "posedge",
                               "negedge", "or", "and", "not", "function", "endfunction", "task", "endtask", "generate", "endgenerate", "genvar",
                               "signed", "unsigned", "typedef", "enum", "struct", "packed", "union", "interface", "endinterface", "modport",
                               "package", "endpackage", "import", "export", "class", "endclass", "extends", "virtual", "new", "this", "super",
                               "return", "automatic", "static", "const", "unique", "priority", "property", "endproperty", "assert", "assume",
                               "cover", "sequence", "endsequence", "covergroup", "endgroup", "program", "endprogram", "fork", "join", "join_any",
                               "join_none", "wait", "disable", "supply0", "supply1", "tri", "specify", "endspecify", "string", "void"],
                    lineComments: ["//"], blockComment: ("/*", "*/"), strings: #""(?:\\.|[^"\\\n])*""#,
                    extra: [(#"\b\d*\s*'[sS]?[bBoOdDhH]\s*[0-9a-fA-FxXzZ?_]+"#, .number), (#"`\w+"#, .command), (#"\$\w+"#, .command)])
        case .tcl:
            Grammar(keywords: ["proc", "set", "unset", "if", "else", "elseif", "then", "foreach", "for", "while", "return", "puts", "expr", "source",
                               "package", "require", "namespace", "global", "upvar", "variable", "switch", "catch", "error", "incr", "append",
                               "lappend", "list", "lindex", "llength", "string", "file", "open", "close", "exec", "eval", "break", "continue",
                               "create_clock", "create_generated_clock", "set_property", "get_ports", "get_pins", "get_cells", "get_nets",
                               "get_clocks", "set_input_delay", "set_output_delay", "set_false_path", "set_multicycle_path", "read_vhdl",
                               "read_verilog", "read_xdc", "synth_design", "opt_design", "place_design", "route_design", "write_bitstream",
                               "add_files", "create_project", "launch_runs", "wait_on_run", "vlib", "vmap", "vcom", "vlog", "vsim", "run", "add",
                               "wave", "quit", "set_global_assignment", "set_location_assignment", "set_instance_assignment"],
                    lineComments: ["#"], strings: #""(?:\\.|[^"\\])*""#,
                    extra: [(#"\$\{?[\w:]+\}?"#, .number), (#"-\w+"#, .command)])
        case .yaml:
            Grammar(keywords: ["true", "false", "yes", "no", "on", "off", "null"],
                    lineComments: ["#"],
                    extra: [(#"(?m)^\s*(?:-\s+)?[^\s#:'"][^#:\n]*(?=:(?:\s|$))"#, .command), (#"(?m)^(?:---|\.\.\.)\s*$"#, .keyword),
                            (#"[&*][\w-]+"#, .number), (#"!!?\w+"#, .keyword)])
        case .ini:
            Grammar(lineComments: ["#", ";"],
                    extra: [(#"(?m)^\s*\[[^\]\n]+\]"#, .keyword), (#"(?m)^\s*[^\s=#;\[][^=\n]*?(?=\s*[=:])"#, .command),
                            (#"\b(?:true|false|yes|no|on|off)\b"#, .number)])
        case .xml:
            Grammar(strings: #""[^"]*"|'[^']*'"#,
                    extra: [(#"</?[\w:.-]+|/?>"#, .keyword), (#"\b[\w:.-]+(?=\s*=)"#, .command), (#"&\w+;|&#\w+;"#, .number),
                            (#"(?s)<!\[CDATA\[.*?\]\]>|<\?.*?\?>|<!DOCTYPE[^>]*>"#, .command), (#"(?s)<!--.*?-->"#, .comment)])
        case .css:
            Grammar(lineComments: ["//"], blockComment: ("/*", "*/"),
                    extra: [(#"(?m)^\s*[^{}\n;]+(?=\s*\{)"#, .keyword), (#"[\w-]+(?=\s*:[^:])"#, .command), (#"@[\w-]+"#, .keyword),
                            (#"#[0-9a-fA-F]{3,8}\b|\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms|pt|deg)?\b"#, .number), (#"\$[\w-]+"#, .number)])
        case .sql:
            Grammar(keywords: ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create",
                               "table", "drop", "alter", "add", "column", "index", "view", "join", "inner", "left", "right", "outer", "full", "on",
                               "as", "group", "by", "order", "having", "limit", "offset", "union", "all", "distinct", "null", "is", "in", "like",
                               "between", "exists", "case", "when", "then", "else", "end", "primary", "key", "foreign", "references", "unique",
                               "default", "integer", "int", "text", "varchar", "char", "boolean", "date", "timestamp", "real", "float", "begin",
                               "commit", "rollback", "transaction", "with", "returning", "asc", "desc", "count", "sum", "avg", "min", "max"],
                    caseInsensitive: true, lineComments: ["--"], blockComment: ("/*", "*/"))
        case .lua:
            Grammar(keywords: ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not",
                               "or", "repeat", "return", "then", "true", "until", "while", "self", "require"],
                    lineComments: ["--"], blockComment: ("--[[", "]]"))
        case .ruby:
            Grammar(keywords: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "case", "when", "while", "until", "for", "in",
                               "do", "return", "yield", "begin", "rescue", "ensure", "raise", "self", "nil", "true", "false", "and", "or", "not",
                               "require", "require_relative", "include", "extend", "attr_accessor", "attr_reader", "attr_writer", "lambda",
                               "proc", "then", "super", "next", "break", "source", "gem", "group", "task", "namespace", "desc"],
                    lineComments: ["#"], extra: [(#":\w+"#, .number), (#"@{1,2}\w+"#, .command)])
        case .perl:
            Grammar(keywords: ["my", "our", "local", "sub", "if", "elsif", "else", "unless", "while", "until", "for", "foreach", "return", "use",
                               "require", "package", "last", "next", "print", "printf", "die", "warn", "eq", "ne", "lt", "gt", "le", "ge", "and",
                               "or", "not", "undef", "shift", "push", "pop", "open", "close"],
                    lineComments: ["#"], extra: [(#"[$@%][\w:]+"#, .command)])
        case .php:
            Grammar(keywords: ["function", "class", "interface", "trait", "extends", "implements", "public", "private", "protected", "static",
                               "return", "if", "else", "elseif", "foreach", "for", "while", "as", "new", "echo", "print", "null", "true", "false",
                               "namespace", "use", "require", "require_once", "include", "include_once", "array", "try", "catch", "throw",
                               "switch", "case", "default", "break", "continue", "fn", "match", "const", "abstract", "final"],
                    lineComments: ["//", "#"], blockComment: ("/*", "*/"), extra: [(#"\$\w+"#, .command), (#"<\?php|\?>"#, .keyword)])
        case .r:
            Grammar(keywords: ["function", "if", "else", "for", "while", "repeat", "in", "next", "break", "return", "TRUE", "FALSE", "NULL", "NA",
                               "Inf", "NaN", "library", "require", "source"],
                    lineComments: ["#"], extra: [(#"<<?-|->>?"#, .keyword)])
        case .julia:
            Grammar(keywords: ["function", "end", "if", "elseif", "else", "for", "while", "in", "return", "module", "using", "import", "export",
                               "struct", "mutable", "abstract", "type", "begin", "let", "local", "global", "const", "do", "try", "catch",
                               "finally", "true", "false", "nothing", "macro", "quote", "where", "break", "continue"],
                    lineComments: ["#"], blockComment: ("#=", "=#"), strings: #""(?:\\.|[^"\\\n])*""#, extra: [(#"@\w+"#, .command)])
        case .dockerfile:
            Grammar(keywords: ["FROM", "RUN", "CMD", "COPY", "ADD", "ENV", "ARG", "WORKDIR", "EXPOSE", "ENTRYPOINT", "USER", "VOLUME", "LABEL",
                               "HEALTHCHECK", "SHELL", "STOPSIGNAL", "ONBUILD", "MAINTAINER", "AS"],
                    lineComments: ["#"], extra: [(#"\$\{[^}]*\}|\$\w+"#, .number)])
        case .assembly:
            Grammar(lineComments: [";", "#", "//", "@"], blockComment: ("/*", "*/"),
                    extra: [(#"(?m)^\s*\.\w+"#, .keyword), (#"(?m)^\s*[\w.$]+:"#, .command), (#"%\w+|\b[xwrv]\d{1,2}\b|\b(?:[re]?[abcd]x|[re]?[sd]i|[re]?[sb]p|r\d{1,2}[dwb]?|sp|lr|pc)\b"#, .command),
                            (#"#?-?\b0[xX][0-9a-fA-F]+\b|#-?\d+"#, .number)])
        case .fortran:
            Grammar(keywords: ["program", "end", "module", "use", "implicit", "none", "integer", "real", "double", "precision", "complex", "logical",
                               "character", "parameter", "dimension", "allocatable", "intent", "in", "out", "inout", "subroutine", "function",
                               "call", "return", "if", "then", "else", "elseif", "endif", "do", "enddo", "while", "select", "case", "contains",
                               "type", "print", "write", "read", "allocate", "deallocate", "stop", "exit", "cycle", "result", "pure", "elemental",
                               "recursive", "interface", "only", "public", "private", ".true.", ".false.", ".and.", ".or.", ".not."],
                    caseInsensitive: true, lineComments: ["!"])
        case .haskell:
            Grammar(keywords: ["module", "where", "import", "qualified", "as", "hiding", "data", "type", "newtype", "class", "instance", "deriving",
                               "let", "in", "case", "of", "if", "then", "else", "do", "forall", "True", "False", "Nothing", "Just"],
                    lineComments: ["--"], blockComment: ("{-", "-}"), strings: #""(?:\\.|[^"\\\n])*""#)
        case .matlab:
            Grammar(keywords: ["function", "end", "if", "elseif", "else", "for", "parfor", "while", "switch", "case", "otherwise", "try", "catch",
                               "return", "break", "continue", "global", "persistent", "classdef", "properties", "methods", "events",
                               "enumeration", "arguments", "spmd", "true", "false", "pi", "Inf", "NaN", "nargin", "nargout", "varargin", "varargout"],
                    lineComments: ["%"], blockComment: ("%{", "%}"),
                    strings: #""(?:""|[^"\n])*"|(?<![\w\])}.'])'(?:''|[^'\n])*'"#)
        case .spice:
            Grammar(keywords: [".subckt", ".ends", ".model", ".param", ".include", ".inc", ".lib", ".endl", ".tran", ".ac", ".dc", ".op", ".noise",
                               ".end", ".option", ".options", ".print", ".plot", ".probe", ".measure", ".meas", ".global", ".ic", ".nodeset",
                               ".temp", ".step", ".save", ".control", ".endc", ".func", ".four", ".sens", ".tf", ".alter", ".data", ".enddata",
                               "dec", "oct", "lin", "pulse", "sin", "pwl", "exp", "sffm", "uic"],
                    caseInsensitive: true, lineComments: [";", "$ "], strings: #""[^"\n]*"|'[^'\n]*'"#,
                    extra: [(#"(?im)^[rclvikmqdxjebsgfhtwou]\w*"#, .command),
                            (#"(?i)\b\d+(?:\.\d+)?(?:e[+-]?\d+)?(?:meg|mil|[fpnumkgt])?\b"#, .number),
                            (#"(?m)^\s*\*.*$"#, .comment)])
        case .linker:
            Grammar(keywords: ["SECTIONS", "MEMORY", "ENTRY", "OUTPUT_FORMAT", "OUTPUT_ARCH", "OUTPUT", "INPUT", "GROUP", "INCLUDE", "SEARCH_DIR",
                               "STARTUP", "PROVIDE", "PROVIDE_HIDDEN", "HIDDEN", "KEEP", "ALIGN", "ORIGIN", "LENGTH", "SIZEOF", "ADDR",
                               "LOADADDR", "AT", "FILL", "ASSERT", "DEFINED", "NOLOAD", "ABSOLUTE", "MAX", "MIN", "PHDRS", "SORT",
                               "SORT_BY_NAME", "SORT_BY_ALIGNMENT", "EXCLUDE_FILE", "COMMON", "CONSTRUCTORS", "BYTE", "SHORT", "LONG", "QUAD",
                               "ORIGIN", "INSERT", "AFTER", "BEFORE", "REGION_ALIAS"],
                    lineComments: ["//"], blockComment: ("/*", "*/"), strings: #""[^"\n]*""#,
                    extra: [(#"(?<![\w)])\.[A-Za-z_][\w.]*"#, .command), (#"\b0[xX][0-9a-fA-F]+\b|\b\d+[KMG]\b"#, .number)])
        case .fpga:
            Grammar(keywords: ["net", "inst", "loc", "iostandard", "period", "timespec", "tnm_net", "tnm", "pullup", "pulldown", "keeper", "drive",
                               "slew", "offset", "in", "out", "before", "after", "high", "low", "fast", "slow", "set_io", "set_frequency",
                               "locate", "comp", "site", "iobuf", "port", "frequency", "mhz", "ns", "sysconfig", "blkname", "bank", "vccio",
                               "io_type", "pull_mode", "use", "primary", "clock_dedicated_route", "false", "true", "set_iobank", "set_io_type",
                               "assign_net_macro", "set_location", "set_clock"],
                    caseInsensitive: true, lineComments: ["#", "//"], strings: #""[^"\n]*""#,
                    extra: [(#"(?<=\s)-\w+"#, .command)])
        case .gnuplot:
            Grammar(keywords: ["set", "unset", "plot", "splot", "replot", "using", "with", "lines", "points", "linespoints", "boxes", "errorbars",
                               "title", "notitle", "xlabel", "ylabel", "zlabel", "xrange", "yrange", "zrange", "terminal", "term", "output", "for",
                               "in", "do", "if", "else", "while", "fit", "via", "pause", "reset", "load", "call", "print", "linetype", "lt", "lw",
                               "linewidth", "pt", "pointtype", "ps", "pointsize", "lc", "linecolor", "axis", "axes", "grid", "key", "logscale",
                               "style", "every", "smooth", "datafile", "separator", "format", "tics", "xtics", "ytics", "mxtics", "mytics",
                               "size", "font", "multiplot", "origin", "palette", "border", "label", "arrow", "dashtype", "dt"],
                    lineComments: ["#"], extra: [(#"\$\w+"#, .number)])
        case .scala:
            Grammar(keywords: ["def", "val", "var", "class", "object", "trait", "extends", "with", "case", "match", "if", "else", "for", "yield",
                               "while", "do", "return", "new", "this", "super", "import", "package", "private", "protected", "override",
                               "implicit", "lazy", "sealed", "abstract", "final", "type", "given", "using", "then", "enum", "export", "true",
                               "false", "null", "try", "catch", "finally", "throw", "Module", "IO", "Input", "Output", "Flipped", "Reg",
                               "RegInit", "RegNext", "RegEnable", "Wire", "WireDefault", "WireInit", "UInt", "SInt", "Bool", "Vec", "VecInit",
                               "Bundle", "Mem", "SyncReadMem", "when", "elsewhen", "otherwise", "switch", "is", "Mux", "MuxCase", "Cat", "Fill"],
                    lineComments: ["//"], blockComment: ("/*", "*/"),
                    strings: #"(?s:""".*?""")|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])'"#,
                    extra: [(#"@\w+"#, .command), (#"\b\d+\.(?:U|S|B|W)\b"#, .number)])
        case .kotlin:
            Grammar(keywords: ["fun", "val", "var", "class", "object", "interface", "data", "sealed", "enum", "companion", "if", "else", "when",
                               "for", "while", "do", "return", "in", "is", "as", "by", "init", "constructor", "this", "super", "null", "true",
                               "false", "try", "catch", "finally", "throw", "import", "package", "private", "public", "protected", "internal",
                               "override", "open", "abstract", "lateinit", "suspend", "inline", "reified", "typealias", "where", "out",
                               "vararg", "const", "annotation", "inner", "value", "break", "continue", "it"],
                    lineComments: ["//"], blockComment: ("/*", "*/"),
                    strings: #"(?s:""".*?""")|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])'"#,
                    extra: [(#"@\w+"#, .command), (#"\$\{[^}]*\}|\$\w+"#, .number)])
        case .csharp:
            Grammar(keywords: ["using", "namespace", "class", "struct", "interface", "enum", "record", "public", "private", "protected", "internal",
                               "static", "readonly", "const", "void", "int", "long", "double", "float", "decimal", "bool", "char", "byte",
                               "string", "object", "var", "dynamic", "if", "else", "for", "foreach", "in", "while", "do", "switch", "case",
                               "default", "break", "continue", "return", "new", "this", "base", "null", "true", "false", "try", "catch",
                               "finally", "throw", "async", "await", "virtual", "override", "abstract", "sealed", "partial", "get", "set",
                               "init", "value", "out", "ref", "params", "is", "as", "typeof", "nameof", "where", "yield", "lock", "event",
                               "delegate", "operator", "implicit", "explicit", "checked", "unchecked", "fixed", "unsafe", "required", "with"],
                    lineComments: ["//"], blockComment: ("/*", "*/"),
                    strings: #"@"(?:""|[^"])*"|\$?"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])'"#,
                    extra: [(#"(?m)^\s*#\s*\w+"#, .command), (#"(?m)^\s*\[[\w.]+(?:\([^)\n]*\))?\]"#, .command)])
        case .powershell:
            Grammar(keywords: ["function", "param", "begin", "process", "end", "if", "elseif", "else", "foreach", "for", "while", "do", "until",
                               "switch", "return", "try", "catch", "finally", "throw", "break", "continue", "in", "class", "enum", "using",
                               "filter", "trap", "exit", "-eq", "-ne", "-gt", "-lt", "-ge", "-le", "-like", "-notlike", "-match", "-notmatch",
                               "-and", "-or", "-not", "-contains", "-notcontains", "-in", "-notin", "-replace", "-split", "-join", "-is", "-as"],
                    caseInsensitive: true, lineComments: ["#"], blockComment: ("<#", "#>"),
                    extra: [(#"\$[\w:]+|\$\{[^}]*\}"#, .command), (#"\b[A-Z][a-z]+-[A-Z]\w+"#, .command), (#"\[[\w.\[\]]+\]"#, .number)])
        case .batch:
            Grammar(keywords: ["echo", "set", "if", "else", "for", "in", "do", "goto", "call", "exit", "not", "exist", "defined", "errorlevel",
                               "equ", "neq", "lss", "leq", "gtr", "geq", "setlocal", "endlocal", "enabledelayedexpansion", "enableextensions",
                               "off", "on", "pause", "shift", "start", "cd", "chdir", "pushd", "popd", "copy", "xcopy", "move", "del", "mkdir",
                               "md", "rmdir", "rd", "type", "cls", "title", "choice", "timeout", "nul"],
                    caseInsensitive: true, lineComments: ["::"], strings: #""[^"\n]*""#,
                    extra: [(#"%~?[\w]+%?|%%~?\w|![\w]+!"#, .number), (#"(?m)^\s*:\w+"#, .command), (#"(?im)^\s*@?rem\b.*$"#, .comment)])
        case .awk:
            Grammar(keywords: ["BEGIN", "END", "BEGINFILE", "ENDFILE", "function", "func", "if", "else", "while", "for", "in", "do", "break",
                               "continue", "next", "nextfile", "exit", "return", "delete", "getline", "print", "printf", "NR", "NF", "FS",
                               "OFS", "RS", "ORS", "FILENAME", "FNR", "SUBSEP", "ARGC", "ARGV", "ENVIRON", "length", "substr", "index", "split",
                               "sub", "gsub", "match", "sprintf", "tolower", "toupper", "system"],
                    lineComments: ["#"], strings: #""(?:\\.|[^"\\\n])*""#, extra: [(#"\$\w+|\$\d+"#, .command)])
        case .sed:
            Grammar(lineComments: ["#"], strings: #"(?!)"#,
                    extra: [(#"(?m)^\s*(?:\d+|\$|/[^/\n]*/)?(?:,(?:\d+|\$|/[^/\n]*/))?\s*!?[aicdDgGhHlnNpPqQrRwWxyz=]"#, .keyword),
                            (#"\bs(.)(?:\\.|(?!\1).)*\1(?:\\.|(?!\1).)*\1[gpiIwemM0-9]*"#, .string)])
        case .m4:
            Grammar(lineComments: ["dnl", "#"], strings: #""(?:\\.|[^"\\\n])*""#,
                    extra: [(#"\b[A-Z][A-Z0-9_]{2,}(?=\()"#, .command), (#"\b(?:m4_\w+|define|ifdef|ifelse|include|divert)\b"#, .keyword),
                            (#"\$\{[^}]*\}|\$\w+|\$\d"#, .number), (#"[\[\]]"#, .keyword)])
        case .vim:
            Grammar(keywords: ["set", "setlocal", "let", "unlet", "if", "else", "elseif", "endif", "for", "endfor", "while", "endwhile", "function",
                               "function!", "endfunction", "return", "call", "execute", "exe", "map", "nmap", "imap", "vmap", "noremap",
                               "nnoremap", "inoremap", "vnoremap", "xnoremap", "autocmd", "au", "augroup", "syntax", "highlight", "hi",
                               "colorscheme", "filetype", "plugin", "indent", "on", "off", "source", "runtime", "command", "try", "catch",
                               "endtry", "finally", "throw", "echo", "echom", "silent", "normal", "def", "enddef", "vim9script"],
                    strings: #"'(?:''|[^'\n])*'|(?<=[=(,\s])"(?:\\.|[^"\\\n])*"(?=\s*[,)\n.]|\s*$)"#,
                    extra: [(#"\b[gslabwtv]:\w+|&\w+|<[\w-]+>"#, .number), (#"(?m)^\s*".*$"#, .comment)])
        case .hcl:
            Grammar(keywords: ["resource", "data", "variable", "output", "locals", "module", "provider", "terraform", "backend",
                               "required_providers", "required_version", "for_each", "count", "depends_on", "lifecycle", "dynamic", "content",
                               "true", "false", "null", "for", "in", "if", "each", "var", "local", "path", "job", "group", "task"],
                    lineComments: ["#", "//"], blockComment: ("/*", "*/"), strings: #""(?:\\.|[^"\\\n])*"|<<-?(\w+)[\s\S]*?^\s*\1$"#,
                    extra: [(#"(?m)^\s*[\w-]+(?=\s*=)"#, .command)])
        case .nix:
            Grammar(keywords: ["let", "in", "with", "rec", "inherit", "if", "then", "else", "assert", "import", "true", "false", "null", "or",
                               "builtins", "pkgs", "lib", "self", "super", "callPackage", "mkDerivation", "fetchurl", "fetchFromGitHub"],
                    lineComments: ["#"], blockComment: ("/*", "*/"), strings: #""(?:\\.|[^"\\])*"|''[\s\S]*?''"#,
                    extra: [(#"[\w.-]+(?=\s*=[^=])"#, .command), (#"(?<![\w.])\.{0,2}/[\w./+-]+|<[\w./+-]+>"#, .number)])
        case .meson:
            Grammar(keywords: ["if", "elif", "else", "endif", "foreach", "endforeach", "and", "or", "not", "in", "true", "false", "break",
                               "continue"],
                    lineComments: ["#"], strings: #"(?s:'''.*?''')|f?'(?:\\.|[^'\\\n])*'"#, extra: [(#"\b\w+(?=\s*\()"#, .command)])
        case .ninja:
            Grammar(keywords: ["rule", "build", "default", "pool", "include", "subninja", "command", "description", "depfile", "deps",
                               "generator", "restat", "rspfile", "rspfile_content", "phony", "depth", "msvc_deps_prefix", "dyndep"],
                    lineComments: ["#"], strings: #"(?!)"#,
                    extra: [(#"\$\{?\w+\}?|\$[$:\n ]"#, .number), (#"(?m)^\s*\w+(?=\s*=)"#, .command)])
        case .just:
            Grammar(keywords: ["set", "alias", "export", "import", "mod", "if", "else", "true", "false"],
                    lineComments: ["#"], strings: #"(?s:'''.*?'''|""".*?""")|"(?:\\.|[^"\\\n])*"|'[^'\n]*'"#,
                    extra: [(#"(?m)^@?[\w-]+(?=[^=\n]*:(?!=))"#, .command), (#"\{\{[^}]*\}\}"#, .number), (#"(?m)^\s*\[[\w(), "-]+\]"#, .keyword)])
        case .protobuf:
            Grammar(keywords: ["syntax", "edition", "package", "import", "public", "weak", "option", "message", "enum", "service", "rpc", "returns",
                               "stream", "repeated", "optional", "required", "oneof", "map", "reserved", "extend", "extensions", "to", "max",
                               "true", "false", "double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32", "fixed64",
                               "sfixed32", "sfixed64", "bool", "string", "bytes"],
                    lineComments: ["//"], blockComment: ("/*", "*/"))
        case .graphql:
            Grammar(keywords: ["query", "mutation", "subscription", "fragment", "on", "type", "interface", "union", "enum", "input", "scalar",
                               "schema", "extend", "directive", "implements", "repeatable", "true", "false", "null", "ID", "String", "Int",
                               "Float", "Boolean"],
                    lineComments: ["#"], strings: #"(?s:""".*?""")|"(?:\\.|[^"\\\n])*""#,
                    extra: [(#"\$\w+"#, .command), (#"@\w+"#, .command)])
        case .template:
            withExtra(grammar(for: .xml)!, [(#"(?s)\{\{.*?\}\}|\{%.*?%\}"#, .command), (#"(?s)\{#.*?#\}|\{\{!--.*?--\}\}|\{\{![^}]*\}\}"#, .comment)])
        case .elixir:
            Grammar(keywords: ["def", "defp", "defmodule", "defstruct", "defprotocol", "defimpl", "defmacro", "defmacrop", "defguard",
                               "defexception", "defdelegate", "do", "end", "if", "else", "unless", "case", "cond", "with", "fn", "when", "in",
                               "and", "or", "not", "true", "false", "nil", "import", "alias", "require", "use", "raise", "rescue", "try",
                               "catch", "after", "receive", "quote", "unquote", "for"],
                    lineComments: ["#"], strings: #"(?s:""".*?""")|"(?:\\.|[^"\\])*""#,
                    extra: [(#"(?<![:\w]):[a-z_]\w*[?!]?|\b\w+:(?=\s)"#, .number), (#"@\w+"#, .command), (#"\b[A-Z]\w*(?:\.[A-Z]\w*)*"#, .command)])
        case .erlang:
            Grammar(keywords: ["after", "and", "andalso", "band", "begin", "bnot", "bor", "bsl", "bsr", "bxor", "case", "catch", "cond", "div", "end",
                               "fun", "if", "let", "not", "of", "or", "orelse", "receive", "rem", "try", "when", "xor", "true", "false",
                               "undefined", "ok", "error"],
                    lineComments: ["%"], strings: #""(?:\\.|[^"\\\n])*""#,
                    extra: [(#"(?m)^-\w+"#, .command), (#"\?\w+"#, .command), (#"'(?:\\.|[^'\\\n])*'"#, .number)])
        case .ocaml:
            Grammar(keywords: ["let", "in", "rec", "and", "if", "then", "else", "match", "with", "function", "fun", "type", "of", "module", "struct",
                               "sig", "end", "open", "include", "begin", "val", "mutable", "exception", "try", "raise", "when", "as", "for",
                               "to", "downto", "do", "done", "while", "true", "false", "not", "ref", "external", "functor", "lazy", "method",
                               "object", "class", "inherit", "private", "virtual", "constraint", "assert"],
                    blockComment: ("(*", "*)"), strings: #""(?:\\.|[^"\\])*""#)
        case .fsharp:
            Grammar(keywords: ["let", "in", "rec", "and", "if", "then", "elif", "else", "match", "with", "function", "fun", "type", "of", "module",
                               "namespace", "open", "member", "override", "abstract", "default", "val", "mutable", "new", "do", "done", "for",
                               "to", "downto", "while", "yield", "return", "use", "async", "task", "true", "false", "not", "null", "interface",
                               "inherit", "struct", "end", "begin", "exception", "try", "finally", "raise", "failwith", "when", "as", "static",
                               "private", "public", "internal", "inline", "lazy", "upcast", "downcast"],
                    lineComments: ["//"], blockComment: ("(*", "*)"), strings: #"(?s:""".*?""")|\$?"(?:\\.|[^"\\])*""#,
                    extra: [(#"\[<[^>]*>\]"#, .command), (#"(?m)^\s*#\w+"#, .command)])
        case .clojure:
            Grammar(keywords: ["def", "defn", "defn-", "defmacro", "defmulti", "defmethod", "defprotocol", "defrecord", "deftype", "let", "letfn",
                               "fn", "if", "if-let", "when", "when-let", "when-not", "cond", "condp", "case", "do", "loop", "recur", "ns",
                               "require", "import", "use", "nil", "true", "false", "and", "or", "not", "try", "catch", "finally", "throw",
                               "doseq", "dotimes", "for", "->", "->>", "some->", "as->", "binding", "quote"],
                    lineComments: [";"], strings: #""(?:\\.|[^"\\])*""#,
                    extra: [(#"(?<![\w-]):[\w.*+!?<>=/-]+"#, .number), (#"\\(?:newline|space|tab|\w)"#, .number), (#"#\{|#\(|#_|@|\^"#, .command)])
        case .lisp:
            Grammar(keywords: ["defun", "defmacro", "defvar", "defparameter", "defconst", "defcustom", "defstruct", "defclass", "defmethod",
                               "defgeneric", "let", "let*", "letrec", "flet", "labels", "lambda", "if", "cond", "case", "when", "unless", "progn",
                               "prog1", "setq", "setf", "define", "define-syntax", "define-record-type", "syntax-rules", "quote", "and", "or",
                               "not", "loop", "do", "dolist", "dotimes", "car", "cdr", "cons", "list", "nil", "t", "else", "begin", "require",
                               "provide", "interactive", "save-excursion", "with-current-buffer", "use-package", "module", "struct"],
                    lineComments: [";"], blockComment: ("#|", "|#"), strings: #""(?:\\.|[^"\\])*""#,
                    extra: [(#"(?<![\w-])'[\w*+!?<>=/-]+|(?<![\w-]):[\w-]+|#[tf]\b|#\\\S+"#, .number)])
        case .zig:
            Grammar(keywords: ["const", "var", "fn", "pub", "return", "if", "else", "while", "for", "switch", "break", "continue", "defer", "errdefer",
                               "try", "catch", "orelse", "struct", "enum", "union", "error", "opaque", "comptime", "inline", "export", "extern",
                               "test", "unreachable", "null", "undefined", "true", "false", "and", "or", "usingnamespace", "async", "await",
                               "anytype", "type", "void", "bool", "usize", "isize", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f16",
                               "f32", "f64", "noreturn", "anyerror", "packed", "align", "volatile", "allowzero", "threadlocal", "noalias"],
                    lineComments: ["//"], strings: #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])+'|(?m:\\\\.*$)"#, extra: [(#"@\w+"#, .command)])
        case .nim:
            Grammar(keywords: ["proc", "func", "method", "iterator", "template", "macro", "let", "var", "const", "type", "object", "enum", "tuple",
                               "ref", "ptr", "if", "elif", "else", "when", "case", "of", "for", "while", "in", "notin", "is", "isnot", "return",
                               "yield", "break", "continue", "import", "from", "include", "export", "and", "or", "not", "xor", "shl", "shr",
                               "div", "mod", "true", "false", "nil", "discard", "defer", "try", "except", "finally", "raise", "block", "static",
                               "distinct", "concept", "converter", "using", "result", "echo"],
                    lineComments: ["#"], blockComment: ("#[", "]#"), strings: #"(?s:""".*?""")|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])'"#,
                    extra: [(#"\{\.[^}]*\.\}"#, .command)])
        case .pascal:
            Grammar(keywords: ["program", "unit", "uses", "interface", "implementation", "begin", "end", "var", "const", "type", "procedure",
                               "function", "if", "then", "else", "case", "of", "for", "to", "downto", "do", "while", "repeat", "until", "with",
                               "record", "array", "set", "string", "integer", "real", "boolean", "char", "byte", "word", "longint", "cardinal",
                               "double", "true", "false", "nil", "and", "or", "not", "xor", "div", "mod", "shl", "shr", "in", "is", "as",
                               "class", "object", "constructor", "destructor", "inherited", "private", "public", "protected", "published",
                               "property", "try", "except", "finally", "raise", "exit", "result", "initialization", "finalization", "self",
                               "override", "virtual", "abstract", "overload", "forward", "label", "goto", "file", "packed"],
                    caseInsensitive: true, lineComments: ["//"], blockComment: ("{", "}"), strings: #"'(?:''|[^'\n])*'"#,
                    extra: [(#"\$[0-9A-Fa-f]+\b|#\d+"#, .number), (#"\(\*[\s\S]*?\*\)"#, .comment)])
        case .ada:
            Grammar(keywords: ["procedure", "function", "package", "body", "is", "begin", "end", "if", "then", "elsif", "else", "case", "when",
                               "others", "loop", "for", "while", "in", "out", "return", "declare", "type", "subtype", "record", "array", "of",
                               "with", "use", "null", "new", "access", "all", "constant", "renames", "exception", "raise", "private", "limited",
                               "tagged", "abstract", "task", "entry", "accept", "select", "protected", "generic", "not", "and", "or", "xor",
                               "mod", "rem", "abs", "exit", "goto", "pragma", "range", "digits", "delta", "true", "false", "integer", "natural",
                               "positive", "boolean", "string", "float", "character", "reverse", "until", "delay", "terminate", "interface",
                               "overriding", "some", "aliased", "separate", "do", "at"],
                    caseInsensitive: true, lineComments: ["--"], strings: #""(?:""|[^"\n])*"|'.'(?!\w)"#,
                    extra: [(#"'\w+"#, .command)])
        case .mathematica:
            Grammar(keywords: ["Module", "Block", "With", "Function", "If", "Which", "Switch", "Do", "For", "While", "Table", "Map", "Apply",
                               "Select", "Return", "True", "False", "Null", "Print", "Plot", "ListPlot", "Integrate", "D", "Solve", "NSolve",
                               "Simplify", "FullSimplify", "Length", "Range", "Sum", "Product", "Part", "Join", "Import", "Export", "Needs",
                               "BeginPackage", "EndPackage", "Begin", "End"],
                    blockComment: ("(*", "*)"), strings: #""(?:\\.|[^"\\])*""#,
                    extra: [(#"\b[A-Z]\w*(?=\[)"#, .command), (#"#\d*|\b\w+_\w*"#, .number)])
        case .json, .tex, .bibtex, .markdown, .diff, .plain, .typst, .rst, .asciidoc, .org, .subtitles:
            nil
        }
    }

    private static func withExtra(_ grammar: Grammar, _ extra: [(pattern: String, role: Role)]) -> Grammar {
        var grammar = grammar
        grammar.extra += extra
        return grammar
    }

    static func highlight(_ text: String, language: Language?, dark: Bool) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.textColor])
        guard let language, language != .plain else { return result }
        let colors = (keyword: dark ? NSColor(hex: "#FF7AB2") : NSColor(hex: "#AD3DA4"),
                      string: dark ? NSColor(hex: "#FC6A5D") : NSColor(hex: "#C41A16"),
                      comment: dark ? NSColor(hex: "#7F8C98") : NSColor(hex: "#5D6C79"),
                      number: dark ? NSColor(hex: "#D9C97C") : NSColor(hex: "#1C00CF"),
                      command: dark ? NSColor(hex: "#6BDFFF") : NSColor(hex: "#0F68A0"),
                      added: dark ? NSColor(hex: "#67D77A") : NSColor(hex: "#1E7F34"),
                      removed: dark ? NSColor(hex: "#FF6B6B") : NSColor(hex: "#B42318"))
        func color(_ role: Role) -> NSColor {
            switch role {
            case .keyword: colors.keyword
            case .string: colors.string
            case .comment: colors.comment
            case .number: colors.number
            case .command: colors.command
            case .added: colors.added
            case .removed: colors.removed
            }
        }
        func apply(_ pattern: String, _ color: NSColor, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                result.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        switch language {
        case .json:
            apply(#""(?:\\.|[^"\\])*"\s*:"#, colors.keyword)
            apply(#":\s*"(?:\\.|[^"\\])*""#, colors.string)
            apply(#"\b-?\d+(\.\d+)?([eE][+-]?\d+)?\b|\b(true|false|null)\b"#, colors.number)
        case .tex:
            apply(#"\\[A-Za-z@]+"#, colors.command)
            apply(#"\$[^$]*\$"#, colors.number)
            apply(#"(?<!\\)%.*$"#, colors.comment, options: .anchorsMatchLines)
        case .bibtex:
            // Champs (author =), valeurs entre accolades ou guillemets, commandes LaTeX, type d'entrée et clé de citation.
            apply(#"^\s*[A-Za-z][\w-]*(?=\s*=)"#, colors.command, options: .anchorsMatchLines)
            apply(#"(?<==\s{0,20})(?:\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}|"(?:\\.|[^"\\])*")"#, colors.string)
            apply(#"(?<==\s{0,20})\d+\b"#, colors.number)
            apply(#"\\[A-Za-z@]+"#, colors.command)
            apply(#"@[A-Za-z]+"#, colors.keyword)
            apply(#"(?<=@[A-Za-z]{1,30}\{)\s*[^,\s{}]+"#, colors.number)
            // Commentaire en début de ligne seulement : les % des URL restent dans la valeur.
            apply(#"^\s*%.*$"#, colors.comment, options: .anchorsMatchLines)
        case .typst:
            apply(#"(?m)^\s*=+ .*$"#, colors.keyword, options: .anchorsMatchLines)
            apply(#"#[A-Za-z_][\w-]*(?:\.[A-Za-z_][\w-]*)*"#, colors.command)
            apply(#"\$[^$]*\$"#, colors.number)
            apply(#"<[\w:.-]+>|@[\w:.-]+"#, colors.number)
            apply(#""(?:\\.|[^"\\\n])*"|`[^`\n]*`"#, colors.string)
            apply(#"(?<![:\w])//.*$"#, colors.comment, options: .anchorsMatchLines)
            apply(#"/\*[\s\S]*?\*/"#, colors.comment)
        case .rst:
            apply(#"(?m)^([=\-~^"'`#*+:._])\1{2,}\s*$"#, colors.keyword, options: .anchorsMatchLines)
            apply(#"(?m)^\s*\.\. [\w:-]+::"#, colors.command, options: .anchorsMatchLines)
            apply(#":[\w:-]+:(?=`)|(?m)^\s*:[\w -]+:(?=\s)"#, colors.command, options: .anchorsMatchLines)
            apply(#"\*\*[^*\n]+\*\*|`[^`\n]+`_{0,2}"#, colors.number)
            apply(#"``[^`\n]+``"#, colors.string)
            apply(#"(?m)^\.\.(?: (?![\w:-]+::|_|\[|\|).*)?$"#, colors.comment, options: .anchorsMatchLines)
        case .asciidoc:
            apply(#"(?m)^=+ .*$|(?m)^\.\S.*$"#, colors.keyword, options: .anchorsMatchLines)
            apply(#"(?m)^:[\w-]+!?:"#, colors.command, options: .anchorsMatchLines)
            apply(#"\b[\w-]+::?[^\s\[]*\[[^\]\n]*\]|\{[\w-]+\}"#, colors.command)
            apply(#"\*[^*\n]+\*"#, colors.number)
            apply(#"`[^`\n]+`|(?m)^(?:----|\.\.\.\.|====|\*\*\*\*|____|\+\+\+\+)\s*$"#, colors.string, options: .anchorsMatchLines)
            apply(#"(?m)^//(?!/).*$"#, colors.comment, options: .anchorsMatchLines)
        case .org:
            apply(#"(?m)^\*+ .*$"#, colors.keyword, options: .anchorsMatchLines)
            apply(#"\b(?:TODO|DONE|NEXT|WAITING|CANCELLED)\b"#, colors.removed)
            apply(#"(?im)^\s*#\+\w+:?"#, colors.command, options: .anchorsMatchLines)
            apply(#"\[\[[^\]\n]*\](?:\[[^\]\n]*\])?\]|<\d{4}-\d{2}-\d{2}[^>\n]*>"#, colors.command)
            apply(#"(?<!\w)[~=][^~=\n]+[~=](?!\w)"#, colors.string)
            apply(#"(?m)^\s*# .*$"#, colors.comment, options: .anchorsMatchLines)
        case .subtitles:
            apply(#"(?m)^\d+\s*$|^WEBVTT.*$"#, colors.number, options: .anchorsMatchLines)
            apply(#"(?:\d{2}:)?\d{2}:\d{2}[,.]\d{3}\s*-->\s*(?:\d{2}:)?\d{2}:\d{2}[,.]\d{3}.*"#, colors.command)
            apply(#"</?[a-z]+[^>\n]*>|\{\\[^}\n]*\}"#, colors.keyword)
            apply(#"(?m)^NOTE\b.*$"#, colors.comment, options: .anchorsMatchLines)
        case .markdown:
            apply(#"^#{1,6} .*$"#, colors.keyword, options: .anchorsMatchLines)
            apply(#"`[^`\n]+`|^```.*$"#, colors.string, options: .anchorsMatchLines)
            apply(#"\*\*[^*\n]+\*\*|\[[^\]\n]+\]\([^)\n]+\)"#, colors.command)
        case .diff:
            apply(#"^\+.*$"#, colors.added, options: .anchorsMatchLines)
            apply(#"^-.*$"#, colors.removed, options: .anchorsMatchLines)
            apply(#"^@@.*$"#, colors.command, options: .anchorsMatchLines)
            apply(#"^(?:diff|index|\+\+\+|---) .*$"#, colors.keyword, options: .anchorsMatchLines)
        default:
            guard let grammar = grammar(for: language) else { return result }
            if !grammar.keywords.isEmpty {
                let escaped = grammar.keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
                apply(#"(?<![\w#.$@-])(\#(escaped))(?![\w-])"#, colors.keyword, options: grammar.caseInsensitive ? .caseInsensitive : [])
            }
            apply(#"\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#, colors.number)
            for (pattern, role) in grammar.extra where role != .comment { apply(pattern, color(role)) }
            // Chaînes et commentaires en une passe, de gauche à droite : le premier qui commence l'emporte
            // (un « // » dans une chaîne n'ouvre pas de commentaire, un guillemet dans un commentaire n'ouvre pas de chaîne).
            var comments = grammar.lineComments.map { prefix -> String in
                // « # » en début de mot seulement (pas dans $# ni dans une couleur CSS).
                let escaped = NSRegularExpression.escapedPattern(for: prefix)
                return (prefix == "#" ? #"(?<![\w$&{])"# : "") + escaped + #"[^\n]*"#
            }
            if let block = grammar.blockComment {
                comments.insert(NSRegularExpression.escapedPattern(for: block.open) + #"[\s\S]*?(?:"# + NSRegularExpression.escapedPattern(for: block.close) + "|$)", at: 0)
            }
            let combined = "(" + grammar.strings + ")" + (comments.isEmpty ? "" : "|(" + comments.joined(separator: "|") + ")")
            if let regex = try? NSRegularExpression(pattern: combined) {
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let isString = match.range(at: 1).location != NSNotFound
                    result.addAttribute(.foregroundColor, value: isString ? colors.string : colors.comment, range: match.range)
                }
            }
            for (pattern, role) in grammar.extra where role == .comment { apply(pattern, color(role)) }
        }
        return result
    }
}
