=begin pod

=head1 NAME

OpenRouter::API::Result::Provider - One provider from GET /providers

=head1 SYNOPSIS

=begin code :lang<raku>

my @ps = $or.get-providers;
for @ps -> $p {
    say $p.name, " (", $p.slug, ") — ", $p.headquarters;
    say "  datacenters: ", $p.datacenters.join(", ");
}

=end code

=end pod

unit class OpenRouter::API::Result::Provider;

has %!data;

submethod BUILD(:%!data) { }

method new(:%data --> OpenRouter::API::Result::Provider:D) {
	self.bless(:%data);
}

method name(--> Str)            { %!data<name> }
method slug(--> Str)            { %!data<slug> }
method headquarters(--> Str)    { %!data<headquarters> }
method privacy-policy-url(--> Str) { %!data<privacy_policy_url> }
method terms-of-service-url(--> Str) { %!data<terms_of_service_url> }
method status-page-url(--> Str) { %!data<status_page_url> }

method datacenters(--> List) {
	(%!data<datacenters> // []).List;
}

method raw(--> Hash) { %!data.Hash }
