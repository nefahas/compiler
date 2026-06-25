return {
	syntax_tokens = {
		['('] = 'LPAR',
		[')'] = 'RPAR',
		['{'] = 'LCURLY',
		['}'] = 'RCURLY',
		['['] = 'LBRACK',
		[']'] = 'RBRACK',
		['*'] = 'STAR',
		['&'] = 'AMPER',
		[';'] = 'SEMICOLON',
		[','] = 'COMMA',
		
		['"'] = 'QUOTE',
		['\''] = 'APOST',
		['/'] = 'SLASH',
		['+'] = 'PLUS',
		['-'] = 'MINUS',
		['<'] = 'LT',
		['>'] = 'GT',
		['='] = 'ASSIGN',
		['=='] = 'EQUALS',
		['<='] = 'LTE',
		['>='] = 'GTE',
		['!'] = 'NOT',
		['!='] = 'NEQ',
		
		['|'] = 'BOR',
		['^'] = 'XOR',
		['~'] = 'BNOT',
	},
	
	keywords = {
		['char'] = 'CHAR',
		['int'] = 'INT',
		['void'] = 'VOID',
		
		['extern'] = 'EXTERN',
		['return'] = 'RETURN',
		['asm'] = 'ASM',
		
		['if'] = 'IF',
		['while'] = 'WHILE',
		['for'] = 'FOR',
		['else'] = 'ELSE',
		['break'] = 'BREAK',
		
		['struct'] = 'STRUCT',
	},
	
	types = {
		'CHAR',
		'INT',
		'VOID',
		'STRUCT',
	}
}
