=begin pod

=head1 NAME

OpenRouter::API::Result::Endpoint - One provider endpoint for a model

=head1 SYNOPSIS

=begin code :lang<raku>

my @endpoints = $or.get-model-endpoints('anthropic', 'claude-opus-4-7');
my $cheapest = @endpoints.sort(*.input-price-per-token).head;
say $cheapest.provider-name, "  \$", $cheapest.input-price-per-token,
    "/tok in, ctx ", $cheapest.context-length;

=end code

=head1 DESCRIPTION

Wraps a single entry from the C<endpoints> array of
C<GET /models/{author}/{slug}/endpoints>, or from
C<GET /endpoints/zdr>. Exposes provider, pricing, context, quant,
uptime, latency, and ZDR flags.

Prices come back as C<Rat> in USD-per-token (OpenRouter's wire
format is a string).

=end pod

unit class OpenRouter::API::Result::Endpoint;

has %!data;

submethod BUILD(:%!data) { }

method new(:%data --> OpenRouter::API::Result::Endpoint:D) {
	self.bless(:%data);
}

method name(--> Str)                 { %!data<name> }
method provider-name(--> Str)        { %!data<provider_name> }
method model-id(--> Str)             { %!data<model_id> }
method model-name(--> Str)           { %!data<model_name> }
method tag(--> Str)                  { %!data<tag> }
method quantization(--> Str)         { %!data<quantization> }
method context-length(--> Int)       { %!data<context_length> // 0 }
method max-completion-tokens(--> Int){ %!data<max_completion_tokens> // Int }
method max-prompt-tokens(--> Int)    { %!data<max_prompt_tokens> // Int }

method supported-parameters(--> List) {
	(%!data<supported_parameters> // []).List;
}

method input-price-per-token(--> Rat) {
	self!parse-price(%!data<pricing><prompt>);
}

method output-price-per-token(--> Rat) {
	self!parse-price(%!data<pricing><completion>);
}

method input-cache-read-price-per-token(--> Rat) {
	self!parse-price(%!data<pricing><input_cache_read>);
}

method input-cache-write-price-per-token(--> Rat) {
	self!parse-price(%!data<pricing><input_cache_write>);
}

#|( Numeric OpenRouter health status. Wire meaning: 0 = healthy,
    non-zero = degraded or quarantined. Exposed verbatim so callers
    can compare; the upstream docs are the source of truth on
    specific values. )
method status(--> Int) { %!data<status> // 0 }

# Time-windowed accessors mirror the wire snake_case because kebab-
# case identifiers can't have a digit right after a hyphen —
# `uptime-last-30m` would be parsed as `uptime-last - 30m` (a
# subtraction of a duration literal).
method uptime_last_30m(--> Numeric) { %!data<uptime_last_30m> // 0 }
method uptime_last_5m(--> Numeric)  { %!data<uptime_last_5m>  // 0 }
method uptime_last_1d(--> Numeric)  { %!data<uptime_last_1d>  // 0 }

method latency_last_30m(--> Numeric)    { %!data<latency_last_30m> }
method throughput_last_30m(--> Numeric) { %!data<throughput_last_30m> }

method supports-implicit-caching(--> Bool:D) {
	%!data<supports_implicit_caching> // False;
}

method raw(--> Hash) { %!data.Hash }

method !parse-price($v --> Rat) {
	return Rat unless $v.defined;
	return try { $v.Rat } // Rat;
}
