=begin pod

=head1 NAME

OpenRouter::API - Raku client for OpenRouter's non-inference REST API

=head1 SYNOPSIS

=begin code :lang<raku>

use OpenRouter::API;

# Reads OPENROUTER_API_KEY from %*ENV by default.
my $or = OpenRouter::API::Client.new;

# Full model catalogue, cached in-process for 5 minutes.
my @models = $or.get-models;

# Keyword / capability / cost filtering (all client-side; OR has no
# server-side name search). Hits the cached catalogue.
my @claude = $or.search-models(
    :keyword<claude-opus>,
    :supports-tool-use,
    :min-context-length(200_000),
);

# Credit balance.
my $credits = $or.get-credits;
say "${$credits.remaining} USD left";

# Daily spending log — last 30 UTC days. REQUIRES A MANAGEMENT KEY.
my @rows = $or.get-activity(:date<2026-04-23>);
say @rows.map(*.cost).sum, " USD spent on 2026-04-23";

# Per-call cost lookup. Pass a Str gen-id or any object with a
# .generation-id method (e.g. LLM::Chat::Backend::Response::OpenRouter).
my $gen = $or.get-generation('gen-abc123');
my $g2  = $or.get-generation($llm-chat-response);   # duck-typed

=end code

=head1 DESCRIPTION

Thin wrapper over OpenRouter's REST surface for everything that isn't
chat / text inference. Inference lives in
L<LLM::Chat::Backend::OpenRouter>; this module is for tooling that
needs to read models, track spend, or look up generations after the
fact.

Design goals:

=item B<Typed results with an escape hatch.> Every endpoint returns
      a C<Result::*> object with named accessors and derived helpers
      (C<Model.cheapest-endpoint>, C<ActivityRow.cost-per-1k-tokens>,
      ...). C<.raw> exposes the wire hash verbatim for fields we
      haven't typed yet.

=item B<Tier 0 dependency.> The only external deps are
      C<Cro::HTTP::Client> and C<JSON::Fast>. The
      L<LLM::Chat::Backend::Response::OpenRouter> integration is
      duck-typed via C<.can('generation-id')> so you get the
      convenience without the dependency direction being inverted.

=item B<Cached model catalogue.> C<search-models> goes through a
      5-minute TTL cache — the catalogue is hundreds of KB and
      rarely changes, so repeated filters don't round-trip. Disable
      with C<:cache(False)> on the Client, or call C<.clear-cache>
      to invalidate.

=item B<No inference.> C<POST /chat/completions> is deliberately
      absent. Use L<LLM::Chat::Backend::OpenRouter> for that.

=head1 SEE ALSO

=item L<OpenRouter::API::Client> - the Client class and its methods.
=item L<OpenRouter::API::Filter> - the model-filter predicate used by C<search-models>.
=item L<OpenRouter::API::Result::Model> and siblings under C<Result::*>.
=item L<LLM::Chat::Backend::OpenRouter> - inference-side OR backend.
=item L<https://openrouter.ai/docs/api-reference/overview> - upstream API docs.

=end pod

unit module OpenRouter::API;

use OpenRouter::API::Client;
use OpenRouter::API::Filter;
use OpenRouter::API::Result::ActivityRow;
use OpenRouter::API::Result::Credits;
use OpenRouter::API::Result::Endpoint;
use OpenRouter::API::Result::Generation;
use OpenRouter::API::Result::Model;
use OpenRouter::API::Result::Provider;
