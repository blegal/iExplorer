import AppKit

/// Coloration syntaxique légère par expressions régulières (sans dépendance).
/// Le langage se déduit du nom du fichier (Makefile, CMakeLists.txt, Dockerfile…) puis de son extension.
enum SyntaxHighlighter {
    enum Language {
        case swift, cFamily, python, javascript, java, go, rust, shell, json, tex, bibtex, markdown, plain
        case make, cmake, vhdl, verilog, tcl, yaml, ini, xml, css, sql, lua, ruby, perl, php, r, julia
        case dockerfile, assembly, fortran, haskell, diff

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
            case .plain: "Texte"
            case .make: "Makefile"
            case .cmake: "CMake"
            case .vhdl: "VHDL"
            case .verilog: "Verilog / SystemVerilog"
            case .tcl: "Tcl"
            case .yaml: "YAML"
            case .ini: "Configuration"
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
            case .assembly: "Assembleur"
            case .fortran: "Fortran"
            case .haskell: "Haskell"
            case .diff: "Diff"
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
        case ".gitignore", ".gitattributes", ".gitmodules", ".gitconfig", ".dockerignore", ".editorconfig", ".npmrc", ".env": return .ini
        default: break
        }
        if name.lowercased().hasPrefix("dockerfile.") { return .dockerfile }
        if name.lowercased().hasPrefix("makefile.") { return .make }
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "c", "h", "cpp", "hpp", "cc", "hh", "cxx", "hxx", "inl", "ipp", "m", "mm", "cu", "cuh", "cl", "ino", "glsl", "vert", "frag", "metal", "hlsl": return .cFamily
        case "py", "pyw", "pyi": return .python
        case "js", "mjs", "cjs", "ts", "tsx", "jsx", "mts", "cts": return .javascript
        case "java", "kt", "kts", "scala", "cs", "groovy", "gradle", "dart": return .java
        case "go": return .go
        case "rs": return .rust
        case "sh", "bash", "zsh", "fish", "ksh", "command": return .shell
        case "json", "geojson", "jsonc": return .json
        case "tex", "sty", "cls", "ltx", "dtx": return .tex
        case "bib": return .bibtex
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "mk", "mak", "make": return .make
        case "cmake": return .cmake
        case "vhd", "vhdl", "vho", "vht": return .vhdl
        case "v", "vh", "sv", "svh", "svi": return .verilog
        case "tcl", "xdc", "sdc", "do", "tk", "qsf", "upf": return .tcl
        case "yaml", "yml": return .yaml
        case "toml", "ini", "cfg", "conf", "properties", "desktop", "service", "env": return .ini
        case "xml", "html", "htm", "xhtml", "svg", "plist", "xsd", "xsl", "xslt", "storyboard", "xib", "vue", "ui", "qrc": return .xml
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
        case "txt", "log", "csv", "tsv": return .plain
        default: return nil
        }
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
                    extra: [(#"(?m)^\s*#\s*\w+"#, .command), (#"\b0[xX][0-9a-fA-F]+[uUlL]*\b"#, .number)])
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
        case .json, .tex, .bibtex, .markdown, .diff, .plain:
            nil
        }
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
