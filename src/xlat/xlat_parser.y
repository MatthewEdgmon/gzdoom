
%token_prefix XLAT_
%token_type {FParseToken}
%token_destructor {}	// just to avoid a compiler warning
%name XlatParse
%extra_argument { FParseContext *context }
%syntax_error { context->PrintError("syntax error");}


main ::= translation_unit.

translation_unit ::= . /* empty */
translation_unit ::= translation_unit external_declaration.

external_declaration ::= define_statement.
external_declaration ::= enum_statement.
external_declaration ::= linetype_declaration.
external_declaration ::= boom_declaration.
external_declaration ::= sector_declaration.
external_declaration ::= lineflag_declaration.
external_declaration ::= sector_bitmask.
external_declaration ::= maxlinespecial_def.
external_declaration ::= NOP.


%left OR.
%left XOR.
%left AND.
%left MINUS PLUS.
%left MULTIPLY DIVIDE MODULUS.
%left NEG.

%type exp {int}
exp(A) ::= NUM(B).					{ A = B.val; }
exp(A) ::= exp(B) PLUS exp(C).		{ A = B + C; }
exp(A) ::= exp(B) MINUS exp(C).		{ A = B - C; }
exp(A) ::= exp(B) MULTIPLY exp(C).	{ A = B * C; }
exp(A) ::= exp(B) DIVIDE exp(C).	{ if (C != 0) A = B / C; else context->PrintError("Division by zero"); }
exp(A) ::= exp(B) MODULUS exp(C).	{ if (C != 0) A = B % C; else context->PrintError("Division by zero"); }
exp(A) ::= exp(B) OR exp(C).		{ A = B | C; }
exp(A) ::= exp(B) AND exp(C).		{ A = B & C; }
exp(A) ::= exp(B) XOR exp(C).		{ A = B ^ C; }
exp(A) ::= MINUS exp(B). [NEG]		{ A = -B; }
exp(A) ::= LPAREN exp(B) RPAREN.	{ A = B; }


//==========================================================================
//
// define
//
//==========================================================================

define_statement ::= DEFINE SYM(A) LPAREN exp(B) RPAREN.
{
	context->AddSym (A.sym, B);
}

//==========================================================================
//
// enum
//
//==========================================================================

enum_statement ::= enum_open enum_list RBRACE.

enum_open ::= ENUM LBRACE.
{
	context->EnumVal = 0;
}

enum_list ::= . /* empty */
enum_list ::= single_enum.
enum_list ::= enum_list COMMA single_enum.

single_enum ::= SYM(A).
{
	context->AddSym (A.sym, context->EnumVal++);
}

single_enum ::= SYM(A) EQUALS exp(B).
{
	context->AddSym (A.sym, B);
	context->EnumVal = B+1;
}

//==========================================================================
//
// standard linetype
//
//==========================================================================

%type linetype_exp {int}
linetype_exp(Z) ::= exp(A).
{
	Z = static_cast<XlatParseContext *>(context)->DefiningLineType = A;
}

linetype_declaration ::= linetype_exp(linetype) EQUALS exp(flags) COMMA exp(special) LPAREN special_args(arg) RPAREN.
{
	SimpleLineTranslations.SetVal(linetype, 
		FLineTrans(special&0xffff, flags+arg.addflags, arg.args[0], arg.args[1], arg.args[2], arg.args[3], arg.args[4]));
	static_cast<XlatParseContext *>(context)->DefiningLineType = -1;
}

linetype_declaration ::= linetype_exp EQUALS exp COMMA SYM(S) LPAREN special_args RPAREN.
{
	Printf ("%s, line %d: %s is undefined\n", context->SourceFile, context->SourceLine, S.sym);
	static_cast<XlatParseContext *>(context)->DefiningLineType = -1;
}

%type exp_with_tag {int}
exp_with_tag(A) ::= NUM(B).		{ XlatExpressions.Push(B.val); A = XlatExpressions.Push(XEXP_Const); }
exp_with_tag(A) ::= TAG.									{ A = XlatExpressions.Push(XEXP_Tag); }
exp_with_tag(A) ::= exp_with_tag PLUS exp_with_tag.			{ A = XlatExpressions.Push(XEXP_Add); }
exp_with_tag(A) ::= exp_with_tag MINUS exp_with_tag.		{ A = XlatExpressions.Push(XEXP_Sub); }
exp_with_tag(A) ::= exp_with_tag MULTIPLY exp_with_tag.		{ A = XlatExpressions.Push(XEXP_Mul); }
exp_with_tag(A) ::= exp_with_tag DIVIDE exp_with_tag.		{ A = XlatExpressions.Push(XEXP_Div); }
exp_with_tag(A) ::= exp_with_tag MODULUS exp_with_tag.		{ A = XlatExpressions.Push(XEXP_Mod); }
exp_with_tag(A) ::= exp_with_tag OR exp_with_tag.			{ A = XlatExpressions.Push(XEXP_Or);  }
exp_with_tag(A) ::= exp_with_tag AND exp_with_tag.			{ A = XlatExpressions.Push(XEXP_And); }
exp_with_tag(A) ::= exp_with_tag XOR exp_with_tag.			{ A = XlatExpressions.Push(XEXP_Xor); }
exp_with_tag(A) ::= MINUS exp_with_tag. [NEG]				{ A = XlatExpressions.Push(XEXP_Neg); }
exp_with_tag(A) ::= LPAREN exp_with_tag(B) RPAREN.			{ A = B; }


%type special_arg {SpecialArg}

special_arg(Z) ::= exp_with_tag(A).
{
	if (XlatExpressions[A] == XEXP_Tag)
	{ // Store tags directly
		Z.arg = 0;
		Z.argop = ARGOP_Tag;
		XlatExpressions.Delete(A);
	}
	else
	{ // Try and evaluate it. If it's a constant, store it and erase the
	  // expression. Otherwise, store the index to the expression. We make
	  // no attempt to simplify non-constant expressions.
		FXlatExprState state;
		int val;
		const int *endpt;
		int *xnode;
		
		state.linetype = static_cast<XlatParseContext *>(context)->DefiningLineType;
		state.tag = 0;
		state.bIsConstant = true;
		xnode = &XlatExpressions[A];
		endpt = XlatExprEval[*xnode](&val, xnode, &state);
		if (state.bIsConstant)
		{
			Z.arg = val;
			Z.argop = ARGOP_Const;
			endpt++;
			assert(endpt >= &XlatExpressions[0]);
			XlatExpressions.Resize((unsigned)(endpt - &XlatExpressions[0]));
		}
		else
		{
			Z.arg = A;
			Z.argop = ARGOP_Expr;
		}
	}
}

%type multi_special_arg {SpecialArgs}

multi_special_arg(Z) ::= special_arg(A).
{
	Z.addflags = A.argop << LINETRANS_TAGSHIFT;
	Z.argcount = 1;
	Z.args[0] = A.arg;
	Z.args[1] = 0;
	Z.args[2] = 0;
	Z.args[3] = 0;
	Z.args[4] = 0;
}
multi_special_arg(Z) ::= multi_special_arg(A) COMMA special_arg(B).
{
	Z = A;
	if (Z.argcount < LINETRANS_MAXARGS)
	{
		Z.addflags |= B.argop << (LINETRANS_TAGSHIFT + Z.argcount * TAGOP_NUMBITS);
		Z.args[Z.argcount] = B.arg;
		Z.argcount++;
	}
	else if (Z.argcount++ == LINETRANS_MAXARGS)
	{
		context->PrintError("Line special has too many arguments\n");
	}
}

%type special_args {SpecialArgs}

special_args(Z) ::= . /* empty */
{
	Z.addflags = 0;
	Z.argcount = 0;
	Z.args[0] = 0;
	Z.args[1] = 0;
	Z.args[2] = 0;
	Z.args[3] = 0;
	Z.args[4] = 0;
}
special_args(Z) ::= multi_special_arg(A).
{
	Z = A;
}

//==========================================================================
//
// boom generalized linetypes
//
//==========================================================================

%type list_val {ListFilter}
%type arg_list {MoreFilters *}
%type boom_args {ParseBoomArg}
%type boom_op {int}
%type boom_selector {int}
%type boom_line {FBoomArg}
%type boom_body {MoreLines *}


boom_declaration ::= LBRACKET exp(special) RBRACKET LPAREN exp(firsttype) COMMA exp(lasttype) RPAREN LBRACE boom_body(stores) RBRACE.
{
	int i;
	MoreLines *probe;

	if (NumBoomish == MAX_BOOMISH)
	{
		MoreLines *probe = stores;

		while (probe != NULL)
		{
			MoreLines *next = probe->next;
			delete probe;
			probe = next;
		}
		Printf ("%s, line %d: Too many BOOM translators\n", context->SourceFile, context->SourceLine);
	}
	else
	{
		Boomish[NumBoomish].FirstLinetype = firsttype;
		Boomish[NumBoomish].LastLinetype = lasttype;
		Boomish[NumBoomish].NewSpecial = special;
		
		for (i = 0, probe = stores; probe != NULL; i++)
		{
			MoreLines *next = probe->next;
			Boomish[NumBoomish].Args.Push(probe->arg);
			delete probe;
			probe = next;
		}
		NumBoomish++;
	}
}

boom_body(A) ::= . /* empty */
{
	A = NULL;
}
boom_body(A) ::= boom_line(B) boom_body(C).
{
	A = new MoreLines;
	A->next = C;
	A->arg = B;
}

boom_line(A) ::= boom_selector(sel) boom_op(op) boom_args(args).
{
	A.bOrExisting = (op == OR_EQUAL);
	A.bUseConstant = (args.filters == NULL);
	A.ListSize = 0;
	A.ArgNum = sel;
	A.ConstantValue = args.constant;
	A.AndValue = args.mask;

	if (args.filters != NULL)
	{
		int i;
		MoreFilters *probe;

		for (i = 0, probe = args.filters; probe != NULL; i++)
		{
			MoreFilters *next = probe->next;
			if (i < 15)
			{
				A.ResultFilter[i] = probe->filter.filter;
				A.ResultValue[i] = probe->filter.value;
			}
			else if (i == 15)
			{
				context->PrintError ("Lists can only have 15 elements");
			}
			delete probe;
			probe = next;
		}
		A.ListSize = i > 15 ? 15 : i;
	}
}

boom_selector(A) ::= FLAGS.		{ A = 4; }
boom_selector(A) ::= ARG2.		{ A = 0; }
boom_selector(A) ::= ARG3.		{ A = 1; }
boom_selector(A) ::= ARG4.		{ A = 2; }
boom_selector(A) ::= ARG5.		{ A = 3; }

boom_op(A) ::= EQUALS.			{ A = '='; }
boom_op(A) ::= OR_EQUAL.		{ A = OR_EQUAL; }

boom_args(A) ::= exp(B).
{
	A.constant = B;
	A.filters = NULL;
}
boom_args(A) ::= exp(B) LBRACKET arg_list(C) RBRACKET.
{
	A.mask = B;
	A.filters = C;
}

arg_list(A) ::= list_val(B).
{
	A = new MoreFilters;
	A->next = NULL;
	A->filter = B;
}
arg_list(A) ::= list_val(B) COMMA arg_list(C).
{
	A = new MoreFilters;
	A->next = C;
	A->filter = B;
}

list_val(A) ::= exp(B) COLON exp(C).
{
	A.filter = B;
	A.value = C;
}

//==========================================================================
//
// max line special
//
//==========================================================================

maxlinespecial_def ::= MAXLINESPECIAL EQUALS exp(mx) SEMICOLON.
{
	// Just kill all specials higher than the max.
	// If the translator wants to redefine some later, just let it.
	SimpleLineTranslations.Resize(mx+1);
}

//==========================================================================
//
// sector types
//
//==========================================================================

%type sector_op {int}

sector_declaration ::= SECTOR exp(from) EQUALS exp(to) SEMICOLON.
{
	FSectorTrans tr(to, true);
	SectorTranslations.SetVal(from, tr);
}

sector_declaration ::= SECTOR exp EQUALS SYM(sy) SEMICOLON.
{
	Printf("Unknown constant '%s'\n", sy.sym);
}

sector_declaration ::= SECTOR exp(from) EQUALS exp(to) NOBITMASK SEMICOLON.
{
	FSectorTrans tr(to, false);
	SectorTranslations.SetVal(from, tr);
}

sector_bitmask ::= SECTOR BITMASK exp(mask) sector_op(op) exp(shift) SEMICOLON.
{
	FSectorMask sm = { mask, op, shift};
	SectorMasks.Push(sm);
}

sector_bitmask ::= SECTOR BITMASK exp(mask) SEMICOLON.
{
	FSectorMask sm = { mask, 0, 0};
	SectorMasks.Push(sm);
}

sector_bitmask ::= SECTOR BITMASK exp(mask) CLEAR SEMICOLON.
{
	FSectorMask sm = { mask, 0, 1};
	SectorMasks.Push(sm);
}

sector_op(A) ::= LSHASSIGN.		{ A = 1; }
sector_op(A) ::= RSHASSIGN.		{ A = -1; }

%type lineflag_op {int}

lineflag_declaration ::= LINEFLAG exp(from) EQUALS exp(to) SEMICOLON.
{
	if (from >= 0 && from < 16)
	{
		LineFlagTranslations[from].newvalue = to;
		LineFlagTranslations[from].ismask = false;
	}
}

lineflag_declaration ::= LINEFLAG exp(from) AND exp(mask) SEMICOLON.
{
	if (from >= 0 && from < 16)
	{
		LineFlagTranslations[from].newvalue = mask;
		LineFlagTranslations[from].ismask = true;
	}
}