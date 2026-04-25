=begin pod

=head1 NAME

OpenRouter::API::Filter - Client-side predicates for model filtering

=head1 SYNOPSIS

=begin code :lang<raku>

use OpenRouter::API::Filter;

# Usually reached via Client.search-models, but the predicate is
# exposed directly so callers can build richer queries.
my @matches = $models.grep({
    OpenRouter::API::Filter::matches(
        $_,
        :keyword<claude>,
        :supports-tool-use,
        :min-context-length(200_000),
    )
});

=end code

=head1 DESCRIPTION

Pure-Raku predicates over L<OpenRouter::API::Result::Model>. Every
parameter is optional and conjunctive — omit a parameter to leave
that dimension unfiltered. OpenRouter itself has no server-side
keyword search on C</models>; this module provides the equivalent
client-side.

Population is stubbed here for now; the full predicate lands with
C<Client.search-models> (task 20).

=end pod

unit module OpenRouter::API::Filter;

use OpenRouter::API::Result::Model;

#|( Evaluate every supplied filter against one C<Model>. Returns
    True when the model passes every defined filter, False
    otherwise. An undefined parameter is a no-op for that
    dimension — callers pass only the filters they care about.

    Filter semantics:
    =item C<:$keyword> — case-insensitive substring match against
          the model's C<id>, C<name>, and C<description>. A single
          keyword today; splitting on whitespace + requiring all
          tokens to hit can come later without breaking callers.
    =item C<:$author> — exact match on the C<author/> prefix of the
          model id. E.g. C<:author<anthropic>> matches every
          C<anthropic/*> model.
    =item C<:$max-input-cost> / C<:$max-output-cost> — USD per token
          at the catalogue-level advertised price. A model with
          either price undefined (rare, but happens for free /
          preview models) counts as matching when the limit is
          zero and excluded otherwise, since "unknown price" is
          safer to omit than to silently include when the caller
          set a ceiling.
    =item C<:$min-context-length> — C<context-length >= N>.
    =item C<:$supports-*> — strict Boolean compare against the
          derived capability check. C<:supports-tool-use(True)>
          keeps only models that pass; C<:supports-tool-use(False)>
          keeps only models that don't. Omit to ignore the
          dimension. )
our sub matches(
	OpenRouter::API::Result::Model:D $model,
	Str  :$keyword,
	Str  :$author,
	Rat  :$max-input-cost,
	Rat  :$max-output-cost,
	Int  :$min-context-length,
	Bool :$supports-tool-use,
	Bool :$supports-vision,
	Bool :$supports-reasoning,
	Bool :$supports-structured-outputs,
	--> Bool:D
) is export {
	if $keyword.defined && $keyword.chars {
		my $needle = $keyword.lc;
		my $haystack = ($model.id // '').lc
		             ~ ' ' ~ ($model.name // '').lc
		             ~ ' ' ~ ($model.description // '').lc;
		return False unless $haystack.contains($needle);
	}

	if $author.defined && $author.chars {
		my $m-author = ($model.id // '').split('/', 2).head // '';
		return False unless $m-author eq $author;
	}

	if $max-input-cost.defined {
		my $p = $model.input-price-per-token;
		return False unless $p.defined;
		return False if $p > $max-input-cost;
	}

	if $max-output-cost.defined {
		my $p = $model.output-price-per-token;
		return False unless $p.defined;
		return False if $p > $max-output-cost;
	}

	if $min-context-length.defined {
		return False if $model.context-length < $min-context-length;
	}

	if $supports-tool-use.defined {
		return False unless $model.supports-tool-use == $supports-tool-use;
	}

	if $supports-vision.defined {
		return False unless $model.supports-vision == $supports-vision;
	}

	if $supports-reasoning.defined {
		return False unless $model.supports-reasoning == $supports-reasoning;
	}

	if $supports-structured-outputs.defined {
		return False unless $model.supports-structured-outputs == $supports-structured-outputs;
	}

	True;
}
