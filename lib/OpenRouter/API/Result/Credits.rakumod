=begin pod

=head1 NAME

OpenRouter::API::Result::Credits - Current credit balance

=head1 SYNOPSIS

=begin code :lang<raku>

my $c = $or.get-credits;
say "purchased: \${$c.total-credits}";
say "spent:     \${$c.total-usage}";
say "remaining: \${$c.remaining}";

=end code

=head1 DESCRIPTION

Wraps C<GET /credits>. The upstream shape is just
C<{ total_credits, total_usage }>; the C<.remaining> helper is a
convenience that subtracts them (clamped at zero — OR doesn't
underflow to negative, but the wrapper is defensive).

=end pod

unit class OpenRouter::API::Result::Credits;

has %!data;

submethod BUILD(:%!data) { }

method new(:%data --> OpenRouter::API::Result::Credits:D) {
	self.bless(:%data);
}

method total-credits(--> Numeric) { %!data<total_credits> // 0 }
method total-usage(--> Numeric)   { %!data<total_usage>   // 0 }

#|( Remaining USD. Derived from C<total-credits - total-usage>,
    clamped at zero so a malformed wire response never lets a
    caller think they're in credit when they aren't. )
method remaining(--> Numeric) {
	my $r = self.total-credits - self.total-usage;
	$r < 0 ?? 0 !! $r;
}

method raw(--> Hash) { %!data.Hash }
