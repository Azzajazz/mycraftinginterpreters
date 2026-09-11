package lox

import "core:os"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:strconv"

Token_Type :: enum {
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Semicolon,
    Comma,
    Plus,
    Minus,
    Star,
    Bang,
    Equal,
    BangEqual,
    EqualEqual,
    LessEqual,
    GreaterEqual,
    Less,
    Greater,
    Slash,
    Dot,
    Eof,

    Identifier,
    And, 
    Class, 
    Else, 
    False, 
    For, 
    Fun, 
    If, 
    Nil, 
    Or, 
    Print,
    Return, 
    Super, 
    This, 
    True, 
    Var, 
    While,

    Number,
    String,
}

Token :: struct {
    type: Token_Type,
    code_index: int,
    value: string,
}

Lexer :: struct {
    file_name: string,
    line: int,
    char: int,
    code: string,
    code_index: int,
}

get_line_and_char :: proc(code: string, code_index: int) -> (line: int, char: int) {
    line_start_index: int
    for i in 0..<code_index {
        if code[i] == '\n' {
            line_start_index = i + 1
            line += 1
        }
    }
    char = code_index - line_start_index

    return line, char
}

// @Performance: Some tokens have predefined lengths (e.g. keywords).
get_token_length :: proc(lexer: ^Lexer, token: Token) -> int {
    lexer_copy := lexer^
    lexer_copy.code_index = token.code_index

    start := lexer_copy.code_index
    lex_token(&lexer_copy)
    end := lexer_copy.code_index

    return end - start
}

get_token_code :: proc(lexer: ^Lexer, token: Token) -> string {
    length := get_token_length(lexer, token)
    return lexer.code[token.code_index:token.code_index + length]
}

report_lex_error :: proc(lexer: ^Lexer, token: Token, format: string, args: ..any) {
    line_start_index := token.code_index
    for line_start_index > 0 && lexer.code[line_start_index - 1] != '\n' {
        line_start_index -= 1
    }

    line_end_index := token.code_index
    for line_end_index < len(lexer.code) && lexer.code[line_end_index] != '\n' {
        line_end_index += 1
    }

    line := lexer.code[line_start_index:line_end_index]
    char := token.code_index - line_start_index
    size := get_token_length(lexer, token)

    line_number, char_number := get_line_and_char(lexer.code, token.code_index)

    fmt.eprintf("%v(%v:%v) Error: ", lexer.file_name, line_number + 1, char_number + 1)
    fmt.eprintfln(format, ..args)

    fmt.eprintfln("    %v", line)
    fmt.eprint("    ")
    for _ in 0..<char {
        fmt.eprint(" ")
    }
    for _ in 0..<size {
        fmt.eprint("^")
    }
    fmt.eprintln()
    fmt.eprintln()

    had_error = true
}

expect_token :: proc(lexer: ^Lexer, token_type: Token_Type, code: string = "") -> Token {
    token := lex_token(lexer)
    token_code := get_token_code(lexer, token)

    if token.type != token_type {
        if code == "" {
            report_lex_error(lexer, token, "Expected %v, but got '%v'.", token_type, token_code)
        } else {
            report_lex_error(lexer, token, "Expected '%v', but got '%v'.", code, token_code)
        }
    }

    return token
}

advance_lexer :: proc(lexer: ^Lexer, steps: int) {
    for _ in 0..<steps {
        if lexer.code_index >= len(lexer.code) do break

        c := lexer.code[lexer.code_index]
        lexer.code_index += 1

        if c == '\n' {
            lexer.line += 1
            lexer.char = 0
        } else {
            lexer.char += 1
        }
    }
}

peek_token :: proc(lexer: ^Lexer) -> Token {
    // @Performance: Queue tokens so that we don't have to copy and lex here.
    old_lexer := lexer^
    token := lex_token(lexer)
    lexer^ = old_lexer
    return token
}

lex_token :: proc(lexer: ^Lexer) -> Token {
    token: Token

    for lexer.code_index < len(lexer.code) && (strings.is_ascii_space(cast(rune)lexer.code[lexer.code_index]) || strings.starts_with(lexer.code[lexer.code_index:], "//")){
        for lexer.code_index < len(lexer.code) && strings.is_ascii_space(cast(rune)lexer.code[lexer.code_index]) {
            advance_lexer(lexer, 1)
        }

        // Skip inline comments
        if strings.starts_with(lexer.code[lexer.code_index:], "//") {
            newline_index := strings.index_byte(lexer.code[lexer.code_index:], '\n')
            if newline_index == -1 {
                lexer.code_index = len(lexer.code)
                // Note we don't have to update lexer.line and lexer.char here, since we're at the end of input.
            } else {
                advance_lexer(lexer, newline_index)
            }
        }
    }

    token.code_index = lexer.code_index

    if lexer.code_index >= len(lexer.code) {
        token.type = .Eof
    } else {
        c := lexer.code[lexer.code_index]

        // If we get here, then this is a string literal, a number, an identifier or a keyword.
        if c == '"' {
            // @Robustness: We should probably copy the string value out of the code here.
            string_start_index := lexer.code_index
            advance_lexer(lexer, 1)
            for lexer.code_index < len(lexer.code) && lexer.code[lexer.code_index] != '"' {
                if lexer.code[lexer.code_index] == '\n' {
                    report_lex_error(lexer, token, "Strings must be terminated on the same line they start on.")
                }
                advance_lexer(lexer, 1)
            }

            if lexer.code_index >= len(lexer.code) {
                report_lex_error(lexer, token, "Expected a string to be terminated, but it wasn't.")
            }

            assert(lexer.code[lexer.code_index] == '"')
            advance_lexer(lexer, 1)

            assert(string_start_index <= lexer.code_index - 2)
            token.type = .String
            token.value = lexer.code[string_start_index + 1:lexer.code_index - 1]
        } else if '0' <= c && c <= '9' {
            number_start_index := lexer.code_index

            for lexer.code_index < len(lexer.code) && ('0' <= lexer.code[lexer.code_index] && lexer.code[lexer.code_index] <= '9') {
                advance_lexer(lexer, 1)
            }

            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index] == '.' && ('0' <= lexer.code[lexer.code_index + 1] && lexer.code[lexer.code_index + 1] <= '9') {
                advance_lexer(lexer, 2)

                for lexer.code_index < len(lexer.code) && ('0' <= lexer.code[lexer.code_index] && lexer.code[lexer.code_index] <= '9') {
                    advance_lexer(lexer, 1)
                }
            }

            token.type = .Number
            token.value = lexer.code[number_start_index:lexer.code_index]
        } else if ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || c == '_' {
            lex_identifier_or_keyword(lexer, &token)
        } else {
            switch c {
            case '(':
                token.type = .LeftParen
                advance_lexer(lexer, 1)
            case ')':
                token.type = .RightParen
                advance_lexer(lexer, 1)
            case '{':
                token.type = .LeftBrace
                advance_lexer(lexer, 1)
            case '}':
                token.type = .RightBrace
                advance_lexer(lexer, 1)
            case ';':
                token.type = .Semicolon
                advance_lexer(lexer, 1)
            case ',':
                token.type = .Comma
                advance_lexer(lexer, 1)
            case '+':
                token.type = .Plus
                advance_lexer(lexer, 1)
            case '-':
                token.type = .Minus
                advance_lexer(lexer, 1)
            case '*':
                token.type = .Star
                advance_lexer(lexer, 1)
            case '!':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .BangEqual
                    advance_lexer(lexer, 2)
                } else {
                    token.type = .Bang
                    advance_lexer(lexer, 1)
                }
            case '=':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .EqualEqual
                    advance_lexer(lexer, 2)
                } else {
                    token.type = .Equal
                    advance_lexer(lexer, 1)
                }
            case '<':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .LessEqual
                    advance_lexer(lexer, 2)
                } else {
                    token.type = .Less
                    advance_lexer(lexer, 1)
                }
            case '>':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .GreaterEqual
                    advance_lexer(lexer, 2)
                } else {
                    token.type = .Greater
                    advance_lexer(lexer, 1)
                }
            case '/':
                token.type = .Slash
                advance_lexer(lexer, 1)
            case '.':
                token.type = .Dot
                advance_lexer(lexer, 1)
            case:
                report_lex_error(lexer, token, "Unexpected character '%v'.", cast(rune)c)
            }
        }
    }

    return token
}

lex_identifier_or_keyword :: proc(lexer: ^Lexer, token: ^Token) {
    // This is an identifier.
    identifier_start_index := lexer.code_index
    c1 := lexer.code[lexer.code_index]
    for ('a' <= c1 && c1 <= 'z') || ('A' <= c1 && c1 <= 'Z') || c1 == '_' || ('0' <= c1 && c1 <= '9') {
        advance_lexer(lexer, 1)
        if lexer.code_index >= len(lexer.code) do break
        c1 = lexer.code[lexer.code_index]
    }

    identifier := lexer.code[identifier_start_index:lexer.code_index]

    switch {
    case identifier == "and": 
        token.type = .And
    case identifier == "class": 
        token.type = .Class
    case identifier == "else": 
        token.type = .Else
    case identifier == "false": 
        token.type = .False
    case identifier == "for": 
        token.type = .For
    case identifier == "fun": 
        token.type = .Fun
    case identifier == "if": 
        token.type = .If
    case identifier == "nil": 
        token.type = .Nil
    case identifier == "or": 
        token.type = .Or
    case identifier == "print": 
        token.type = .Print
    case identifier == "return": 
        token.type = .Return
    case identifier == "super": 
        token.type = .Super
    case identifier == "this": 
        token.type = .This
    case identifier == "true": 
        token.type = .True
    case identifier == "var": 
        token.type = .Var
    case identifier == "while":
        token.type = .While
    case:
        token.type = .Identifier
        token.value = identifier
    }
}

dump_token :: proc(lexer: ^Lexer, token: Token) {
    type_str, type_str_ok := reflect.enum_name_from_value(token.type)
    assert(type_str_ok)
    fmt.print(type_str)

    token_code := get_token_code(lexer, token)
    fmt.printf(" %v", token_code)

    if token.type == .Number {
        number, number_ok := strconv.parse_f32(token.value)
        assert(number_ok)
        fmt.printfln(" %v", number)
    } else if token.type == .String {
        fmt.printfln(" %v", token.value)
    } else {
        fmt.println(" null")
    }
}

