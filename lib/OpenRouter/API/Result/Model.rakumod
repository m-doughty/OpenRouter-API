=begin pod

=head1 NAME

OpenRouter::API::Result::Model - One model from OpenRouter's catalogue

=head1 SYNOPSIS

=begin code :lang<raku>

use OpenRouter::API::Client;

my $or = OpenRouter::API::Client.new;
my @models = $or.get-models;

for @models -> $m {
    say $m.id, "  ", $m.name;
    say "  ctx: ",       $m.context-length;
    say "  vision: ",    $m.supports-vision;
    say "  tools: ",     $m.supports-tool-use;
    say "  cheapest $: ", $m.input-price-per-token // 'n/a';
}

=end code

=head1 DESCRIPTION

Wraps a single entry from C<GET /models>. Named accessors cover the
fields callers reach for most often; C<.raw> returns the wire hash
for anything else. Prices come back as C<Rat> in USD-per-token
(OpenRouter's wire format is a string like C<"0.000005">).

=end pod

unit class OpenRouter::API::Result::Model;

has %!data;

submethod BUILD(:%!data) { }

method new(:%data --> OpenRouter::API::Result::Model:D) {
	self.bless(:%data);
}

#|( Top-level identifier: e.g. C<"anthropic/claude-opus-4.7">. )
method id(--> Str:D) { %!data<id> // '' }

#|( Date-stamped slug: e.g. C<"anthropic/claude-opus-4.7-2026-04-16">.
    Useful when referring to an exact version of a model. )
method canonical-slug(--> Str) { %!data<canonical_slug> }

method name(--> Str)             { %!data<name> }
method description(--> Str)      { %!data<description> }
method context-length(--> Int)   { %!data<context_length> // 0 }

#|( Input modalities (e.g. C<<text image>>). Derived from
    C<architecture.input_modalities>, falling back to the legacy
    C<architecture.modality> string (e.g. C<"text+image->text">)
    when input_modalities isn't set. )
method input-modalities(--> List) {
	return %!data<architecture><input_modalities>.List
		if (%!data<architecture> // {})<input_modalities>:exists;
	my $m = (%!data<architecture> // {})<modality> // '';
	return $m.split('->').head.split('+').List if $m.chars;
	().List;
}

#|( Output modalities (e.g. C<<text>>). Same shape as input-modalities. )
method output-modalities(--> List) {
	return %!data<architecture><output_modalities>.List
		if (%!data<architecture> // {})<output_modalities>:exists;
	my $m = (%!data<architecture> // {})<modality> // '';
	return $m.split('->').tail.split('+').List if $m.contains('->');
	().List;
}

#|( OpenRouter tags (e.g. C<<max_tokens tools structured_outputs>>).
    Used by C<supports-tool-use>, C<supports-structured-outputs>, etc. )
method supported-parameters(--> List) {
	(%!data<supported_parameters> // []).List;
}

method supports-tool-use(--> Bool:D) {
	so self.supported-parameters.any eq 'tools'|'tool_choice';
}

method supports-structured-outputs(--> Bool:D) {
	so self.supported-parameters.any eq 'structured_outputs'|'response_format';
}

method supports-reasoning(--> Bool:D) {
	so self.supported-parameters.any eq 'reasoning'|'include_reasoning';
}

method supports-vision(--> Bool:D) {
	so self.input-modalities.any eq 'image';
}

#|( Advertised prompt-token price (USD / token) at the catalogue
    level. Returns a C<Rat> or Nil if the wire field is absent.
    The catalogue view exposes a single representative price; see
    C<get-model-endpoints> to compare provider-level pricing. )
method input-price-per-token(--> Rat) {
	self!parse-price(%!data<pricing><prompt>);
}

method output-price-per-token(--> Rat) {
	self!parse-price(%!data<pricing><completion>);
}

#|( Is the model tagged as free to call? OR marks free-tier variants
    with C<:free> suffixes, or sets both pricing fields to the
    string C<"0">. Normalises both. )
method is-free(--> Bool:D) {
	return True if self.id.contains(':free');
	my $p = self.input-price-per-token;
	my $c = self.output-price-per-token;
	$p.defined && $p == 0 && $c.defined && $c == 0;
}

#|( Verbatim response hash. Escape hatch for fields the wrapper
    doesn't expose as named accessors. )
method raw(--> Hash) { %!data.Hash }

method !parse-price($v --> Rat) {
	return Rat unless $v.defined;
	# OR sends prices as strings — parse defensively; a malformed
	# value returns Nil rather than throwing.
	return try { $v.Rat } // Rat;
}
