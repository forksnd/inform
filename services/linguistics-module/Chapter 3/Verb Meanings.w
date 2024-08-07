[VerbMeanings::] Verb Meanings.

To abstract the meaning of a verb.

@h What we abstract.
Because this module is concerned with the structure of sentences and not
their meanings, we don't really want to get into what verbs "mean". Instead,
we assume that the tool using this module will assign meanings in some way
that it understands and we do not: the data for the meaning of a verb will
be a pointer to |VERB_MEANING_LINGUISTICS_TYPE|. (In Inform, this will be
a binary predicate.)

By default, there's no meaning at all:

@default VERB_MEANING_LINGUISTICS_TYPE void

@ The "reversal" of a verb is the meaning which exchanges its object and
subject. So the reverse meaning to "A likes B" is "A is liked by B", or
equivalent, "B likes A". We use the |VERB_MEANING_REVERSAL_LINGUISTICS_CALLBACK|
to ask for a reversal to be performed when needed.

=
VERB_MEANING_LINGUISTICS_TYPE *VerbMeanings::reverse_VMT(VERB_MEANING_LINGUISTICS_TYPE *recto) {
	#ifdef VERB_MEANING_REVERSAL_LINGUISTICS_CALLBACK
	return VERB_MEANING_REVERSAL_LINGUISTICS_CALLBACK(recto);
	#endif
	#ifndef VERB_MEANING_REVERSAL_LINGUISTICS_CALLBACK
	return recto;
	#endif
}

@h How this module stores verb meanings.
We can now define an object to wrap up this abstracted idea of verb meaning:

=
typedef struct verb_meaning {
	int take_meaning_reversed; /* |TRUE| if this has been reversed */
	VERB_MEANING_LINGUISTICS_TYPE *regular_meaning; /* in I7, this will be a binary predicate */
	struct special_meaning_holder *special_meaning;
	struct verb *take_meaning_from;
	struct parse_node *where_assigned; /* at which sentence this is assigned to a form */
} verb_meaning;

@ All VMs begin as meaningless, which indicates (e.g.) that no meaning
has been specified.

=
verb_meaning VerbMeanings::meaninglessness(void) {
	verb_meaning vm;
	vm.regular_meaning = NULL;
	vm.special_meaning = NULL;
	vm.take_meaning_reversed = FALSE;
	vm.take_meaning_from = NULL;
	vm.where_assigned = current_sentence;
	return vm;
}

int VerbMeanings::is_meaningless(verb_meaning *vm) {
	vm = VerbMeanings::follow_indirection(vm);
	if (vm == NULL) return TRUE;
	if ((vm->regular_meaning == NULL) && (vm->special_meaning == NULL)) return TRUE;
	return FALSE;
}

@ In practice, we create VMs here. Note that regular and special meanings are
alternatives to each other: you can't have both.

=
verb_meaning VerbMeanings::regular(VERB_MEANING_LINGUISTICS_TYPE *rel) {
	verb_meaning vm = VerbMeanings::meaninglessness();
	vm.regular_meaning = rel;
	return vm;
}

verb_meaning VerbMeanings::special(special_meaning_holder *sm) {
	verb_meaning vm = VerbMeanings::meaninglessness();
	vm.special_meaning = sm;
	return vm;
}

@ You can, however, have neither one, if you instead choose to "indirect" the
meaning -- this means saying "the same meaning as the regular sense of the base
form of a given verb", possibly reversed. Note that
(a) An indirected VM must never be used as the meaning for the base form of a
verb, and therefore
(b) We can never have a situation where a VM indirects to a verb whose meaning
then indirects to something else.

This might be used, for example, to set the meaning of "liked by" to be the
same as the meaning of "likes", but with subject and object reversed. The
indirection then ensures that if the meaning of "likes" changes, its associated
usages "is liking" and "is liked by" automatically change with it.

=
verb_meaning VerbMeanings::indirected(verb *from, int reversed) {
	verb_meaning vm = VerbMeanings::meaninglessness();
	vm.take_meaning_reversed = reversed;
	vm.take_meaning_from = from;
	return vm;
}

@ So the following function only needs to be used once.

=
verb_meaning *VerbMeanings::follow_indirection(verb_meaning *vm) {
	if ((vm) && (vm->take_meaning_from))
		return Verbs::first_unspecial_meaning_of_verb_form(
			Verbs::base_form(
				vm->take_meaning_from));
	return vm;
}

@h Recording where assigned.
This helps Inform with correctly locating problem messages.

=
parse_node *VerbMeanings::get_where_assigned(verb_meaning *vm) {
	if (vm) return vm->where_assigned;
	return NULL;
}

void VerbMeanings::set_where_assigned(verb_meaning *vm, parse_node *pn) {
	if (vm) vm->where_assigned = pn;
	else internal_error("assigned location to null meaning");
}

@h The regular meaning.
This is not as simple as returning the |regular_meaning| field, because we
have to follow any indirection, and reverse if necessary.

=
VERB_MEANING_LINGUISTICS_TYPE *VerbMeanings::get_regular_meaning(verb_meaning *vm) {
	if (vm == NULL) return NULL;
	int rev = vm->take_meaning_reversed;
	vm = VerbMeanings::follow_indirection(vm);
	if (vm == NULL) return NULL;
	VERB_MEANING_LINGUISTICS_TYPE *rel = vm->regular_meaning;
	if ((rev) && (rel)) return VerbMeanings::reverse_VMT(rel);
	return rel;
}

VERB_MEANING_LINGUISTICS_TYPE *VerbMeanings::get_regular_meaning_of_form(verb_form *vf) {
	return VerbMeanings::get_regular_meaning(
		Verbs::first_unspecial_meaning_of_verb_form(vf));
}

@h The special meaning.
This is also not as simple as returning the |regular_meaning| field, because
again we have to follow any indirection. Since we have no good way to modify
a special meaning function, we have to provide a function to tell the user
whether to reverse what that function does.

=
special_meaning_holder *VerbMeanings::get_special_meaning(verb_meaning *vm) {
	vm = VerbMeanings::follow_indirection(vm);
	if (vm == NULL) return NULL;
	return vm->special_meaning;
}

int VerbMeanings::get_reversal_status_of_smf(verb_meaning *vm) {
	if (vm == NULL) return FALSE;
	return vm->take_meaning_reversed;
}

@h Logging.

=
void VerbMeanings::log(OUTPUT_STREAM, void *vvm) {
	verb_meaning *vm = (verb_meaning *) vvm;
	if (vm == NULL) { WRITE("<none>"); return; }
	if (vm->take_meaning_reversed) WRITE("reversed-");
	if (vm->take_meaning_from) WRITE("<$w>=", vm->take_meaning_from);
	VERB_MEANING_LINGUISTICS_TYPE *m = VerbMeanings::get_regular_meaning(vm);
	if (m) {
		#ifdef CORE_MODULE
		WRITE("(%S)", m->debugging_log_name);
		#else
		WRITE("(regular)");
		#endif
	} else if (vm->special_meaning) WRITE("(special)");
	else WRITE("(meaningless)");
}
