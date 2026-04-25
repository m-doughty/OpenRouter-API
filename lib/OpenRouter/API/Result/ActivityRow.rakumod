=begin pod

=head1 NAME

OpenRouter::API::Result::ActivityRow - One daily activity / spending row

=head1 SYNOPSIS

=begin code :lang<raku>

# Requires a management key — see OpenRouter::API::Client.
my @rows = $or.get-activity;
for @rows -> $r {
    printf "%s  %-32s  %6d reqs  \$%7.4f  %d in / %d out\n",
        $r.date, $r.model, $r.requests, $r.cost,
        $r.prompt-tokens, $r.completion-tokens;
}

=end code

=head1 DESCRIPTION

Wraps one entry from C<GET /activity>. Each row aggregates a single
UTC date × model × endpoint × provider. Use
C<cost-per-1k-tokens> when comparing across rows — raw cost is hard
to reason about without dividing by volume.

=end pod

unit class OpenRouter::API::Result::ActivityRow;

has %!data;

submethod BUILD(:%!data) { }

method new(:%data --> OpenRouter::API::Result::ActivityRow:D) {
	self.bless(:%data);
}

method date(--> Str)               { %!data<date> }
method model(--> Str)               { %!data<model> }
method model-permaslug(--> Str)     { %!data<model_permaslug> }
method endpoint-id(--> Str)         { %!data<endpoint_id> }
method provider-name(--> Str)       { %!data<provider_name> }

method requests(--> Int)            { %!data<requests> // 0 }
method prompt-tokens(--> Int)       { %!data<prompt_tokens> // 0 }
method completion-tokens(--> Int)   { %!data<completion_tokens> // 0 }
method reasoning-tokens(--> Int)    { %!data<reasoning_tokens> // 0 }

#|( OpenRouter credits spent (USD) for this row. Paid out of the
    user's OR balance. )
method cost(--> Numeric) { %!data<usage> // 0 }

#|( External-credit spend for BYOK requests — i.e. USD spent on the
    user's own provider account, reimbursed to OR. )
method byok-cost(--> Numeric) { %!data<byok_usage_inference> // 0 }

#|( USD per thousand tokens for this row, computed from C<cost> and
    the sum of prompt + completion tokens. Returns 0 when there's
    no token usage (shouldn't happen in practice, but guards
    against divide-by-zero on a malformed row).

    Named C<cost-per-thousand-tokens> rather than the more natural
    C<cost-per-1k-tokens> because Raku identifiers can't have a
    digit immediately after a hyphen — C<1k-tokens> would parse as
    a subtraction. )
method cost-per-thousand-tokens(--> Rat) {
	my $tokens = self.prompt-tokens + self.completion-tokens;
	return 0.Rat unless $tokens;
	return ((self.cost * 1000) / $tokens).Rat;
}

method raw(--> Hash) { %!data.Hash }
