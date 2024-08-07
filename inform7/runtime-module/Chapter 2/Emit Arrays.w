[EmitArrays::] Emit Arrays.

Here is how bytecode to create ready-initialised arrays of Inter data is emitted.

@h Introduction.
This section provides an API for the rest of the //runtime// and //imperative//
modules to use when creating arrays of data in Inter memory. It's easy to use:

(*) Call //EmitArrays::begin_word// or one of its variants.
(*) Fill the array with its initial values.
(*) Call //EmitArrays::end//.

Unlike the API for emitting functions, this one is re-enterable: that is, a
second array can independently be started while the first is still going on,
provided that the second is completed before the first is resumes.

@h Begin.
Call exactly one of these functions. In each case the kind |K| is only weakly
enforced; it's fine to store arbitrary data with |K| being |NULL|.

=
packaging_state EmitArrays::begin_word(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_WORDS);
	return save;
}

packaging_state EmitArrays::begin_word_by_extent(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_WORDS_BY_EXTENT);
	return save;
}

packaging_state EmitArrays::begin_unchecked(inter_name *name) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, NULL, TRUE, CONST_LIST_FORMAT_WORDS);
	return save;
}

packaging_state EmitArrays::begin_byte(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_BYTES);
	return save;
}

packaging_state EmitArrays::begin_byte_by_extent(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_BYTES_BY_EXTENT);
	return save;
}

packaging_state EmitArrays::begin_bounded(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_B_WORDS);
	return save;
}

packaging_state EmitArrays::begin_verb(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_GRAMMAR);
	return save;
}

packaging_state EmitArrays::begin_inline(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_INLINE);
	return save;
}

@ Sum constants are not really arrays at all, but for difficult reasons to
do with linking we store them as such for now. The idea is that we want a
constant like |CONST1 + CONST2 + CONST3|, in circumstances where we don't
know those values right now -- they may be defined in external kits of Inter
code. We therefore cannot fold those into a constant value yet.

Instead we store this as if it were an array of three entries, with references
to symbols to be defined externally.

=
packaging_state EmitArrays::begin_sum_constant(inter_name *name, kind *K) {
	packaging_state save = Packaging::enter_home_of(name);
	EmitArrays::begin_inner(name, K, FALSE, CONST_LIST_FORMAT_SUM);
	return save;
}

@h Fill.
Next call the following functions to add entries to the array. It's fine to
mix and match the different sorts of entry: we're not trying to make something
which would be a typesafe list in I7, so they can be absolutely any data.

=
void EmitArrays::numeric_entry(inter_ti N) {
	EmitArrays::entry_inner(InterValuePairs::number(N));
}

void EmitArrays::iname_entry(inter_name *iname) {
	inter_symbol *alias;
	if (iname == NULL) alias = InterNames::to_symbol(Hierarchy::find(NOTHING_HL));
	else alias = InterNames::to_symbol(iname);
	EmitArrays::entry_inner(Emit::symbol_to_value_pair(alias));
}

void EmitArrays::null_entry(void) {
	EmitArrays::iname_entry(Hierarchy::find(NULL_HL));
}

void EmitArrays::text_entry(text_stream *content) {
	inter_pair val = InterValuePairs::from_text(Emit::at(), content);
	EmitArrays::entry_inner(val);
}

void EmitArrays::dword_entry(text_stream *content) {
	inter_pair val = InterValuePairs::from_singular_dword(Emit::at(), content);
	EmitArrays::entry_inner(val);
}

void EmitArrays::plural_dword_entry(text_stream *content) {
	inter_pair val = InterValuePairs::from_plural_dword(Emit::at(), content);
	EmitArrays::entry_inner(val);
}

void EmitArrays::generic_entry(inter_pair val) {
	EmitArrays::entry_inner(val);
}

@h End.
And then call this to conclude:

=
void EmitArrays::end(packaging_state save) {
	EmitArrays::end_inner();
	Packaging::exit(Emit::tree(), save);
}

@h Implementation.
The rest of this section is not part of the public API, and shouldn't be called.

The implementation would be easy if it weren't for the re-enterability, which
means we have to store an arbitrary number of half-finished arrays in memory.
We do this with a stack of these objects, one for each such array:

=
typedef struct nascent_array {
	struct inter_symbol *array_name_symbol;
	struct kind *entry_kind;
	inter_ti array_form;
	int space_used;
	int capacity;
	inter_pair *entry_storage;
	CLASS_DEFINITION
} nascent_array;

lifo_stack *emission_array_stack = NULL; /* of |nascent_array| */

nascent_array *EmitArrays::current(void) {
	if (emission_array_stack)
		return TOP_OF_LIFO_STACK(nascent_array, emission_array_stack);
	return NULL;
}

@ Until 2021, Inform went to some trouble to re-use these objects in memory.
The memory saving was not worth the complexity and now we simply throw them away
after each use.

=
nascent_array *EmitArrays::push_new(void) {
	if (emission_array_stack == NULL)
		emission_array_stack = NEW_LIFO_STACK(nascent_array);
	nascent_array *A = CREATE(nascent_array);
	A->capacity = 0;
	A->space_used = 0;
	A->entry_kind = NULL;
	A->array_name_symbol = NULL;
	A->array_form = CONST_LIST_FORMAT_WORDS;
	A->entry_storage = NULL;
	PUSH_TO_LIFO_STACK(A, nascent_array, emission_array_stack);
	return A;
}

nascent_array *EmitArrays::pull(void) {
	if (emission_array_stack)
		return PULL_FROM_LIFO_STACK(nascent_array, emission_array_stack);
	internal_error("no array stack");
	return NULL;
}

@ The various ways an array can begin all merge into this function:

=
void EmitArrays::begin_inner(inter_name *N, kind *K, int unchecked, inter_ti format) {
	inter_symbol *symb = InterNames::to_symbol(N);
	nascent_array *current_A = EmitArrays::push_new();
	current_A->entry_kind = (unchecked)?NULL:(K?K:K_value);
	current_A->array_name_symbol = symb;
	current_A->array_form = format;
}

@ And the various ways to add an entry merge into this one:

=
void EmitArrays::entry_inner(inter_pair val) {
	nascent_array *current_A = EmitArrays::current();
	if (current_A == NULL) internal_error("no nascent array");
	int N = current_A->space_used;
	if (N >= current_A->capacity) @<Quadruple the available storage@>;
	current_A->entry_storage[current_A->space_used++] = val;
}

@<Quadruple the available storage@> =
	int M = 4*(N+1);
	if (current_A->capacity == 0) M = 16;
	inter_pair *old_storage = current_A->entry_storage;
	current_A->entry_storage = Memory::calloc(M, sizeof(inter_pair), EMIT_ARRAY_MREASON);
	for (int i=0; i<current_A->capacity; i++) current_A->entry_storage[i] = old_storage[i];
	if (old_storage) Memory::I7_array_free(old_storage, EMIT_ARRAY_MREASON,
		current_A->capacity, sizeof(inter_pair));
	current_A->capacity = M;

@ There is just one way to end. This is the only point at which any Inter
bytecode is actually emitted, in a single burst, and that ensures that one array
is completely emitted before another one is.

=
void EmitArrays::end_inner(void) {
	nascent_array *current_A = EmitArrays::pull();
	if (current_A == NULL) internal_error("no nascent array");
	inter_symbol *con_s = current_A->array_name_symbol;
	kind *K = current_A->entry_kind;
	inter_ti CID = InterTypes::to_TID(InterBookmark::scope(Emit::at()), InterTypes::unchecked());
	if (K) {
		inter_symbol *con_kind = NULL;
		if (ConstantInstruction::is_a_genuine_list_format(current_A->array_form))
			con_kind = Produce::kind_to_symbol(Kinds::unary_con(CON_list_of, K));
		else
			con_kind = Produce::kind_to_symbol(K);
		if (con_kind) CID = Emit::symbol_id(con_kind);
	}
	inter_tree_node *array_in_progress =
		Inode::new_with_3_data_fields(Emit::at(), CONSTANT_IST, Emit::symbol_id(con_s), CID,
			current_A->array_form, NULL, Emit::baseline());
	int pos = array_in_progress->W.extent;
	Inode::extend_instruction_by(array_in_progress, (unsigned int) (2*(current_A->space_used)));
	for (int i=0; i<current_A->space_used; i++, pos += 2)
		InterValuePairs::set(array_in_progress, pos, current_A->entry_storage[i]);
	Produce::guard(VerifyingInter::instruction(
		Emit::package(), array_in_progress));
	NodePlacement::move_to_moving_bookmark(array_in_progress, Emit::at());
}
