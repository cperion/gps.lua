use crate::diag::ParseError;
use crate::source::Span;
use crate::token::{Token, TokenKind};

pub fn lex(source: &str) -> Result<Vec<Token>, ParseError> {
    Lexer::new(source).lex_all()
}

struct Lexer<'a> {
    source: &'a str,
    pos: usize,
    tokens: Vec<Token>,
}

impl<'a> Lexer<'a> {
    fn new(source: &'a str) -> Self {
        Self {
            source,
            pos: 0,
            tokens: Vec::new(),
        }
    }

    fn lex_all(mut self) -> Result<Vec<Token>, ParseError> {
        while let Some(ch) = self.peek_char() {
            match ch {
                ' ' | '\t' | '\r' => {
                    self.bump_char();
                }
                '\n' => {
                    let start = self.pos;
                    self.bump_char();
                    self.push(TokenKind::Newline, start, self.pos);
                }
                '-' if self.peek_two("--") => {
                    self.skip_comment()?;
                }
                '@' if self.peek_two("@{") => {
                    let start = self.pos;
                    let splice = self.scan_splice()?;
                    self.push(TokenKind::Splice(splice), start, self.pos);
                }
                '(' => self.single(TokenKind::LParen),
                ')' => self.single(TokenKind::RParen),
                '[' => {
                    if self.peek_two("[[") {
                        let start = self.pos;
                        let s = self.scan_long_string()?;
                        self.push(TokenKind::String(s), start, self.pos);
                    } else {
                        self.single(TokenKind::LBracket)
                    }
                }
                ']' => self.single(TokenKind::RBracket),
                '{' => self.single(TokenKind::LBrace),
                '}' => self.single(TokenKind::RBrace),
                ',' => self.single(TokenKind::Comma),
                ':' => self.single(TokenKind::Colon),
                ';' => self.single(TokenKind::Semicolon),
                '.' => self.single(TokenKind::Dot),
                '?' => self.single(TokenKind::Question),
                '@' => self.single(TokenKind::At),
                '+' => self.single(TokenKind::Plus),
                '*' => self.single(TokenKind::Star),
                '/' => self.single(TokenKind::Slash),
                '%' => self.single(TokenKind::Percent),
                '&' => self.single(TokenKind::Amp),
                '|' => self.single(TokenKind::Pipe),
                '~' => {
                    let start = self.pos;
                    self.bump_char();
                    if self.peek_char() == Some('=') {
                        self.bump_char();
                        self.push(TokenKind::NotEq, start, self.pos);
                    } else {
                        self.push(TokenKind::Tilde, start, self.pos);
                    }
                }
                '=' => {
                    let start = self.pos;
                    self.bump_char();
                    if self.peek_char() == Some('=') {
                        self.bump_char();
                        self.push(TokenKind::EqEq, start, self.pos);
                    } else {
                        self.push(TokenKind::Assign, start, self.pos);
                    }
                }
                '<' => {
                    let start = self.pos;
                    self.bump_char();
                    match self.peek_char() {
                        Some('=') => {
                            self.bump_char();
                            self.push(TokenKind::LessEq, start, self.pos);
                        }
                        Some('<') => {
                            self.bump_char();
                            self.push(TokenKind::Shl, start, self.pos);
                        }
                        _ => self.push(TokenKind::Less, start, self.pos),
                    }
                }
                '>' => {
                    let start = self.pos;
                    self.bump_char();
                    match self.peek_char() {
                        Some('=') => {
                            self.bump_char();
                            self.push(TokenKind::GreaterEq, start, self.pos);
                        }
                        Some('>') => {
                            self.bump_char();
                            if self.peek_char() == Some('>') {
                                self.bump_char();
                                self.push(TokenKind::ShrU, start, self.pos);
                            } else {
                                self.push(TokenKind::Shr, start, self.pos);
                            }
                        }
                        _ => self.push(TokenKind::Greater, start, self.pos),
                    }
                }
                '-' => {
                    let start = self.pos;
                    self.bump_char();
                    if self.peek_char() == Some('>') {
                        self.bump_char();
                        self.push(TokenKind::Arrow, start, self.pos);
                    } else {
                        self.push(TokenKind::Minus, start, self.pos);
                    }
                }
                '"' | '\'' => {
                    let start = self.pos;
                    let s = self.scan_short_string(ch)?;
                    self.push(TokenKind::String(s), start, self.pos);
                }
                '0'..='9' => {
                    let start = self.pos;
                    let n = self.scan_number();
                    self.push(TokenKind::Number(n), start, self.pos);
                }
                '_' | 'A'..='Z' | 'a'..='z' => {
                    let start = self.pos;
                    let ident = self.scan_ident();
                    let kind = TokenKind::keyword(&ident).unwrap_or(TokenKind::Ident(ident));
                    self.push(kind, start, self.pos);
                }
                _ => {
                    let span = Span::new(self.pos, self.pos + ch.len_utf8());
                    return Err(ParseError::new(
                        format!("unexpected character {:?}", ch),
                        span,
                    ));
                }
            }
        }

        let eof = self.pos;
        self.tokens.push(Token::new(TokenKind::Eof, Span::new(eof, eof)));
        Ok(self.tokens)
    }

    fn push(&mut self, kind: TokenKind, start: usize, end: usize) {
        self.tokens.push(Token::new(kind, Span::new(start, end)));
    }

    fn single(&mut self, kind: TokenKind) {
        let start = self.pos;
        self.bump_char();
        self.push(kind, start, self.pos);
    }

    fn peek_char(&self) -> Option<char> {
        self.source[self.pos..].chars().next()
    }

    fn bump_char(&mut self) -> Option<char> {
        let ch = self.peek_char()?;
        self.pos += ch.len_utf8();
        Some(ch)
    }

    fn peek_two(&self, s: &str) -> bool {
        self.source[self.pos..].starts_with(s)
    }

    fn skip_comment(&mut self) -> Result<(), ParseError> {
        if self.peek_two("--[[") {
            self.pos += 4;
            while self.pos < self.source.len() && !self.peek_two("]]") {
                self.bump_char();
            }
            if self.pos >= self.source.len() {
                return Err(ParseError::new(
                    "unterminated block comment",
                    Span::new(self.source.len().saturating_sub(2), self.source.len()),
                ));
            }
            self.pos += 2;
            return Ok(());
        }

        while let Some(ch) = self.peek_char() {
            if ch == '\n' {
                break;
            }
            self.bump_char();
        }
        Ok(())
    }

    fn scan_ident(&mut self) -> String {
        let start = self.pos;
        self.bump_char();
        while let Some(ch) = self.peek_char() {
            if ch == '_' || ch.is_ascii_alphanumeric() {
                self.bump_char();
            } else {
                break;
            }
        }
        self.source[start..self.pos].to_string()
    }

    fn scan_number(&mut self) -> String {
        let start = self.pos;
        if self.peek_two("0x") || self.peek_two("0X") {
            self.pos += 2;
            while let Some(ch) = self.peek_char() {
                if ch.is_ascii_hexdigit() {
                    self.bump_char();
                } else {
                    break;
                }
            }
            return self.source[start..self.pos].to_string();
        }

        while let Some(ch) = self.peek_char() {
            if ch.is_ascii_digit() {
                self.bump_char();
            } else {
                break;
            }
        }

        if self.peek_char() == Some('.') {
            let mut iter = self.source[self.pos + 1..].chars();
            if matches!(iter.next(), Some(c) if c.is_ascii_digit()) {
                self.bump_char();
                while let Some(ch) = self.peek_char() {
                    if ch.is_ascii_digit() {
                        self.bump_char();
                    } else {
                        break;
                    }
                }
            }
        }

        if matches!(self.peek_char(), Some('e' | 'E')) {
            let save = self.pos;
            self.bump_char();
            if matches!(self.peek_char(), Some('+' | '-')) {
                self.bump_char();
            }
            let exp_start = self.pos;
            while let Some(ch) = self.peek_char() {
                if ch.is_ascii_digit() {
                    self.bump_char();
                } else {
                    break;
                }
            }
            if self.pos == exp_start {
                self.pos = save;
            }
        }

        self.source[start..self.pos].to_string()
    }

    fn scan_short_string(&mut self, quote: char) -> Result<String, ParseError> {
        let start = self.pos;
        self.bump_char();
        let mut out = String::new();
        while let Some(ch) = self.peek_char() {
            self.bump_char();
            if ch == quote {
                return Ok(out);
            }
            if ch == '\\' {
                let esc = self.peek_char().ok_or_else(|| {
                    ParseError::new("unterminated escape sequence", Span::new(self.pos, self.pos))
                })?;
                self.bump_char();
                out.push(match esc {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '\'' => '\'',
                    '"' => '"',
                    other => other,
                });
            } else {
                out.push(ch);
            }
        }
        Err(ParseError::new("unterminated string literal", Span::new(start, self.pos)))
    }

    fn scan_long_string(&mut self) -> Result<String, ParseError> {
        let start = self.pos;
        self.pos += 2;
        let body_start = self.pos;
        while self.pos < self.source.len() && !self.peek_two("]]") {
            self.bump_char();
        }
        if self.pos >= self.source.len() {
            return Err(ParseError::new("unterminated long string literal", Span::new(start, self.pos)));
        }
        let out = self.source[body_start..self.pos].to_string();
        self.pos += 2;
        Ok(out)
    }

    fn scan_splice(&mut self) -> Result<String, ParseError> {
        let start = self.pos;
        self.pos += 2; // '@{'
        let body_start = self.pos;
        let mut depth = 1usize;
        while let Some(ch) = self.peek_char() {
            match ch {
                '{' => {
                    depth += 1;
                    self.bump_char();
                }
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        let out = self.source[body_start..self.pos].to_string();
                        self.bump_char();
                        return Ok(out);
                    }
                    self.bump_char();
                }
                '\'' | '"' => {
                    let quote = ch;
                    let _ = self.scan_short_string(quote)?;
                }
                '[' if self.peek_two("[[") => {
                    let _ = self.scan_long_string()?;
                }
                '-' if self.peek_two("--") => {
                    self.skip_comment()?;
                }
                _ => {
                    self.bump_char();
                }
            }
        }
        Err(ParseError::new("unterminated splice", Span::new(start, self.pos)))
    }
}
