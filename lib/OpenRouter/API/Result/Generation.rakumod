=begin pod

=head1 NAME

OpenRouter::API::Result::Generation - Post-hoc generation metadata

=head1 SYNOPSIS

=begin code :lang<raku>

# Look up a single call by its gen-id.
my $g = $or.get-generation('gen-abc123');
say "cost: \$", $g.total-cost;
say "latency: {$g.latency} ms";
say "finish: ", $g.finish-reason;
say "provider: ", $g.provider-name;

# Include the stored prompt + completion text (only when request
# logging was enabled on the account).
my $full = $or.get-generation-content($g.id);
say $full.prompt-text;
say $full.completion-text;

=end code

=head1 DESCRIPTION

Unified wrapper over C<GET /generation> and C<GET /generation/content>.
The former returns cost / token / latency metadata; the latter
additionally returns the stored prompt messages and completion text
(when logging is enabled).

The Client merges both responses into a single C<Generation> when
C<get-generation-content> is called — C<prompt-text> /
C<completion-text> / C<reasoning-text> stay Nil unless the content
fetch happened.

=end pod

unit class OpenRouter::API::Result::Generation;

has %!data;           # /generation response
has %!content;        # /generation/content response (optional)

submethod BUILD(:%!data, :%!content) { }

method new(:%data, :%content --> OpenRouter::API::Result::Generation:D) {
	self.bless(:%data, :%content);
}

# --- core identifiers + model routing --------------------------------

method id(--> Str)             { %!data<id> }
method upstream-id(--> Str)    { %!data<upstream_id> }
method model(--> Str)          { %!data<model> }
method provider-name(--> Str)  { %!data<provider_name> }
method api-type(--> Str)       { %!data<api_type> }
method streamed(--> Bool)      { %!data<streamed> // False }
method cancelled(--> Bool)     { %!data<cancelled> // False }
method created-at(--> Str)     { %!data<created_at> }
method finish-reason(--> Str)  { %!data<finish_reason> }
method native-finish-reason(--> Str) { %!data<native_finish_reason> }

# --- usage / cost ----------------------------------------------------

method tokens-prompt(--> Int)               { %!data<tokens_prompt> // 0 }
method tokens-completion(--> Int)           { %!data<tokens_completion> // 0 }
method native-tokens-prompt(--> Int)        { %!data<native_tokens_prompt> // 0 }
method native-tokens-completion(--> Int)    { %!data<native_tokens_completion> // 0 }
method native-tokens-reasoning(--> Int)     { %!data<native_tokens_reasoning> // 0 }
method native-tokens-cached(--> Int)        { %!data<native_tokens_cached> // 0 }

method total-cost(--> Numeric)              { %!data<total_cost> // %!data<usage> // 0 }
method upstream-inference-cost(--> Numeric) { %!data<upstream_inference_cost> }
method cache-discount(--> Numeric)          { %!data<cache_discount> }
method is-byok(--> Bool)                    { %!data<is_byok> // False }

#|( USD per token, derived from C<total-cost> and the sum of prompt
    + completion tokens. Returns 0 when tokens aren't recorded. )
method cost-per-token(--> Numeric) {
	my $tokens = self.tokens-prompt + self.tokens-completion;
	return 0 unless $tokens;
	return self.total-cost / $tokens;
}

# --- latency ---------------------------------------------------------

method latency(--> Int)             { %!data<latency> // 0 }
method generation-time(--> Int)     { %!data<generation_time> // 0 }
method moderation-latency(--> Int)  { %!data<moderation_latency> // 0 }

# --- stored content (only when content-fetch happened) --------------

#|( Stored prompt messages, as an array of C<{role, content}> hashes.
    Only populated when constructed from C<get-generation-content>.
    Returns the empty list otherwise. )
method prompt-messages(--> List) {
	(%!content<input><messages> // []).List;
}

#|( Convenience: join stored prompt-message contents into a single
    string. Returns the empty string when content wasn't fetched. )
method prompt-text(--> Str) {
	self.prompt-messages.map({ $_<content> // '' }).join("\n");
}

method completion-text(--> Str) {
	%!content<output><completion> // '';
}

method reasoning-text(--> Str) {
	%!content<output><reasoning> // '';
}

method has-content(--> Bool:D) {
	%!content.elems.Bool;
}

# --- raw -------------------------------------------------------------

method raw(--> Hash)         { %!data.Hash }
method raw-content(--> Hash) { %!content.Hash }
