=begin pod

=head1 NAME

OpenRouter::API::Pricing - Shared wire-price parsing for Result classes

=head1 SYNOPSIS

=begin code :lang<raku>

use OpenRouter::API::Pricing;

my $p = parse-price(%data<pricing><prompt>);
my $variable = is-price-sentinel(%data<pricing><prompt>);

=end code

=head1 DESCRIPTION

Internal helper used by every C<OpenRouter::API::Result::*> class
that exposes a per-token price (C<Model>, C<Endpoint>). It is in
C<provides> only because those classes load it; it is not part of the
public API. It exists so the sentinel rule below lives in exactly one
place instead of being copy-pasted per class.

OpenRouter sends prices as decimal strings (e.g. C<"0.000005">), but
reserves the literal value C<-1> as a sentinel meaning "variable /
indeterminate" — used on router models (e.g. C<openrouter/auto>)
whose real cost depends on which underlying model a request gets
routed to. C<-1> is never a real price.

=end pod

unit module OpenRouter::API::Pricing;

#|( True iff C<$v> is OpenRouter's C<-1> "variable pricing" sentinel.
    Compares numerically, so the wire strings C<"-1"> and C<"-1.0">,
    and the bare number C<-1>, all count. Any other value — including
    other negative numbers, which are malformed rather than
    sentinel — returns False. )
our sub is-price-sentinel($v --> Bool:D) is export {
	return False unless $v.defined;
	my $n = try { $v.Rat };
	return False unless $n.defined;
	$n == -1;
}

#|( Parses an OpenRouter wire price field (e.g. C<pricing.prompt>)
    into a C<Rat> USD-per-token value. Returns the undefined C<Rat>
    when:
    =item the field is absent,
    =item the value doesn't parse as a number (defensive — a
          malformed value returns undefined rather than throwing),
    =item the value is the C<-1> variable-pricing sentinel (see
          C<is-price-sentinel>) — the real price is unknown /
          model-dependent, not negative one,
    =item the value is any OTHER negative number, which is malformed
          wire data (a price can't be negative) and is reported as
          undefined rather than propagated.

    Callers that need to tell "undefined because variable" apart
    from "undefined because absent/malformed" should call
    C<is-price-sentinel> directly, or use the containing Result
    class's C<has-variable-pricing> helper where one is exposed. Cost
    math must always check C<.defined> before comparing — an
    undefined price is never safe to treat as zero or as "within
    budget". )
our sub parse-price($v --> Rat) is export {
	return Rat unless $v.defined;
	my $n = try { $v.Rat } // Rat;
	return Rat unless $n.defined;
	return Rat if $n < 0;
	$n;
}
