=begin pod

=head1 NAME

OpenRouter::API::Client - HTTP client for OpenRouter's non-inference API

=head1 SYNOPSIS

=begin code :lang<raku>

use OpenRouter::API::Client;

# Reads OPENROUTER_API_KEY from env by default.
my $or = OpenRouter::API::Client.new;

# Explicit key + attribution — shown on OR's rankings page / logs.
my $attr = OpenRouter::API::Client.new(
    :api-key(%*ENV<OPENROUTER_API_KEY>),
    :http-referer<https://example.com/my-tool>,
    :x-title<My Tool>,
);

# No-auth endpoints work without a key.
my $anon = OpenRouter::API::Client.new;
my @all  = $anon.get-models;   # /models is public

=end code

=head1 DESCRIPTION

Owns all HTTP I/O to C<https://openrouter.ai/api/v1>. Public methods
are the per-endpoint wrappers (C<get-models>, C<get-credits>,
C<get-activity>, C<get-generation>, ...). The
L<OpenRouter::API>-level module simply re-exports this class along
with the L<OpenRouter::API::Filter> helper and each
C<Result::*> type.

Internals:

=item Private C<!request> builds the URL (base-url + path + query),
      adds auth + attribution headers, calls C<Cro::HTTP::Client.get>,
      parses JSON, and normalises any failure into a C<die> with
      an C<OpenRouter::API:> prefix.

=item Per-call C<Cro::HTTP::Client.new> — no connection pool, matches
      the established monorepo wrapper convention.

=item Models catalogue cached in-process with a 5-minute TTL via
      C<%!cached-models>. Disabled by C<:cache(False)>; invalidate
      with C<.clear-cache>. Other endpoints never touch the cache.

=head1 ATTRIBUTES

=item C<$.api-key> — OpenRouter Bearer token. Defaults to
      C<%*ENV<OPENROUTER_API_KEY>> via the C<TWEAK> submethod. May
      stay undefined for public endpoints; methods that need a key
      die with a helpful message.
=item C<$.base-url> — overrideable for regional endpoints or mock
      servers. Defaults to C<https://openrouter.ai/api/v1>.
=item C<$.http-referer> — optional C<HTTP-Referer> attribution.
=item C<$.x-title> — optional C<X-Title> attribution.
=item C<$.cache> — whether C<search-models> caches the models
      catalogue. Default True.
=item C<$.cache-ttl> — cache lifetime. Default 5 minutes.

=end pod

use Cro::HTTP::Client;
use JSON::Fast;

use OpenRouter::API::Filter;
use OpenRouter::API::Result::ActivityRow;
use OpenRouter::API::Result::Credits;
use OpenRouter::API::Result::Endpoint;
use OpenRouter::API::Result::Generation;
use OpenRouter::API::Result::Model;
use OpenRouter::API::Result::Provider;

unit class OpenRouter::API::Client;

has Str      $.api-key          is rw;
has Str:D    $.base-url         = 'https://openrouter.ai/api/v1';
has Str      $.http-referer;
has Str      $.x-title;
has Bool:D   $.cache            = True;
has Duration $.cache-ttl        = Duration.new(300);

# Cache of model-catalogue fetches keyed by the query-param tuple.
# Each slot: { fetched-at => Instant, list => @models }. Populated
# by get-models, read by get-models + search-models. Other endpoints
# do not touch this.
has %!cached-models;

#|( Env-var fallback. We intentionally don't die when neither attr
    nor env is set — C</models>, C</models/count>, C</providers>,
    and C</endpoints/zdr> are public, and some callers only need
    those. Methods that do require auth call C<!require-auth> up
    front with a helpful message.

    Guarded so a missing env var doesn't try to assign Any into a
    Str-typed attribute. )
submethod TWEAK {
	return if $!api-key.defined;
	my $env = %*ENV<OPENROUTER_API_KEY>;
	$!api-key = $env if $env.defined && $env.chars;
}

#|( Empty the models catalogue cache. Next C<search-models> / cached
    C<get-models> call re-fetches from the server. Safe to call any
    time. )
method clear-cache() {
	%!cached-models = %();
}

# --- HTTP transport --------------------------------------------------

#|( Core GET request. Builds the URL from C<$.base-url> + C<$path>
    + any C<%query> (string values only — Bool is serialised as
    "true"/"false", numeric values as .Str). Adds Authorization +
    attribution headers. Returns the parsed JSON body as whatever
    JSON::Fast produced (Hash at the top level, usually).

    Underscore-prefixed (rather than C<!>-private) so test subclasses
    can override it to stub the HTTP layer — the cache-behaviour
    tests use this to count network round-trips without actually
    hitting OpenRouter.

    Error handling: any Cro-level or transport failure is caught and
    re-thrown as C<OpenRouter::API: GET /path failed: <reason>> with
    the HTTP status mixed in when available. The C</activity> auth-
    scope mismatch is recognised separately in the calling method
    since it needs a more specific message. )
method _request(Str:D :$path!, :%query) {
	my $url = $!base-url ~ $path;
	if %query.elems {
		$url ~= '?' ~ %query.kv.map(-> $k, $v {
			self!encode-query-param($k) ~ '=' ~ self!encode-query-param($v)
		}).join('&');
	}

	my $client = Cro::HTTP::Client.new(:content-type<application/json>);

	my %headers = self!build-headers;

	my $resp;
	try {
		$resp = await $client.get($url, :%headers);
		CATCH {
			when X::Cro::HTTP::Error {
				my $status = try { .response.status.Int } // 0;
				die "OpenRouter::API: GET $path failed with HTTP $status"
				    ~ (.message ?? ": {.message}" !! '');
			}
			default {
				die "OpenRouter::API: GET $path failed: {.message}";
			}
		}
	}

	my $body = await $resp.body-text;
	my $data;
	try {
		$data = from-json($body);
		CATCH {
			default {
				die "OpenRouter::API: GET $path returned non-JSON body: {.message}";
			}
		}
	}
	return $data;
}

#|( Die with a consistent helpful message when an auth-required
    endpoint is called without C<$.api-key> set. Callers pass the
    method name for the message. )
method !require-auth(Str:D $method-name) {
	return if $!api-key.defined && $!api-key.chars;
	die qq:to/MSG/.chomp;
		OpenRouter::API: $method-name requires an API key.
		Set OPENROUTER_API_KEY in the environment or pass :api-key to
		OpenRouter::API::Client.new.
		MSG
}

#|( Build the headers hash used by every request. Bearer + optional
    attribution only; Cro sets content-type via its own constructor. )
method !build-headers(--> Hash) {
	my %h;
	%h<Authorization> = "Bearer $!api-key"
		if $!api-key.defined && $!api-key.chars;
	%h<HTTP-Referer>  = $!http-referer
		if $!http-referer.defined && $!http-referer.chars;
	%h<X-Title>       = $!x-title
		if $!x-title.defined && $!x-title.chars;
	return %h;
}

#|( Minimal percent-encoding for query-string values. We only need
    the RFC 3986 reserved set that realistically shows up in OR
    query params (commas for list values, spaces, path-safe chars).
    Cro's own URI helpers aren't on the public API, so we keep it
    simple and inline. )
method !encode-query-param($v --> Str) {
	my $s = do given $v {
		when Bool   { $_ ?? 'true' !! 'false' }
		when Cool   { .Str }
		default     { .Str }
	};
	$s.subst(/<-[A..Za..z0..9\-._~]>/, -> $m {
		my $o = $m.Str.ord;
		sprintf '%%%02X', $o;
	}, :g);
}

# --- cache helpers ---------------------------------------------------

#|( Return the cache slot for a given query-param tuple, or Nil if
    the slot is absent or expired. Pure read — never mutates. The
    key is built from the sorted query hash so C<:category<chat>>
    and the same query passed a different way collide. )
method !cached-models-fresh(%query --> List) {
	return Nil unless $!cache;
	my $key = self!cache-key(%query);
	return Nil unless %!cached-models{$key}:exists;
	my %slot = %!cached-models{$key};
	return Nil if now - %slot<fetched-at> > $!cache-ttl;
	return %slot<list>;
}

method !cache-models(%query, @list) {
	return unless $!cache;
	my $key = self!cache-key(%query);
	%!cached-models{$key} = %(
		fetched-at => now,
		list       => @list.List,
	);
}

method !cache-key(%query --> Str) {
	%query.keys.sort.map(-> $k { "$k={%query{$k} // ''}" }).join('&');
}

# --- endpoint methods ------------------------------------------------

#|( C<GET /models>. Full model catalogue. Filters are comma-separated
    lists (List or a comma-joined Str — both accepted).

    Cached by the client when C<$.cache> is True (default): repeated
    calls with the same filter tuple within C<$.cache-ttl> skip the
    round-trip. Use C<:cache(False)> on a per-call basis to force a
    fetch, or C<.clear-cache> to invalidate. )
method get-models(
	:$category,
	:$supported-parameters,
	:$output-modalities,
	Bool:D :$cache = $!cache,
	--> List
) {
	my %query;
	%query<category>             = self!join-filter($category)             if $category.defined;
	%query<supported_parameters> = self!join-filter($supported-parameters) if $supported-parameters.defined;
	%query<output_modalities>    = self!join-filter($output-modalities)    if $output-modalities.defined;

	if $cache {
		with self!cached-models-fresh(%query) -> @hit {
			return @hit;
		}
	}

	my $data = self._request(:path</models>, :%query);
	my @list = ($data<data> // []).map({
		OpenRouter::API::Result::Model.new(:data($_));
	}).List;
	self!cache-models(%query, @list) if $cache;
	return @list;
}

#|( C<GET /models/count>. Filterable by output modality. Returns a
    plain C<Int>. Not cached — the number is cheap enough to round-
    trip and cached models can be stale without the count reflecting
    that. )
method count-models(:$output-modalities --> Int) {
	my %query;
	%query<output_modalities> = self!join-filter($output-modalities) if $output-modalities.defined;
	my $data = self._request(:path</models/count>, :%query);
	($data<data><count> // 0).Int;
}

#|( C<GET /models/user>. Catalogue narrowed to the caller's provider
    preferences, privacy settings, and guardrail policy. Requires a
    key; wire shape matches C</models>. Not cached — user-scoped
    results depend on account state that we can't observe for
    invalidation. )
method get-user-models(--> List) {
	self!require-auth('get-user-models');
	my $data = self._request(:path</models/user>);
	($data<data> // []).map({
		OpenRouter::API::Result::Model.new(:data($_));
	}).List;
}

#|( C<GET /models/{author}/{slug}/endpoints>. Returns the list of
    provider endpoints that can serve this model, along with their
    per-endpoint pricing, context, quantization, and health stats. )
method get-model-endpoints(Str:D $author, Str:D $slug --> List) {
	my $data = self._request(
		:path("/models/{$author}/{$slug}/endpoints"),
	);
	($data<data><endpoints> // []).map({
		OpenRouter::API::Result::Endpoint.new(:data($_));
	}).List;
}

#|( C<GET /providers>. All providers OR can route through, with
    headquarters / privacy / status-page metadata. Public — no key
    required. )
method get-providers(--> List) {
	my $data = self._request(:path</providers>);
	($data<data> // []).map({
		OpenRouter::API::Result::Provider.new(:data($_));
	}).List;
}

#|( C<GET /endpoints/zdr>. All provider endpoints that satisfy
    OpenRouter's zero-data-retention restriction. Public. )
method get-zdr-endpoints(--> List) {
	my $data = self._request(:path</endpoints/zdr>);
	($data<data> // []).map({
		OpenRouter::API::Result::Endpoint.new(:data($_));
	}).List;
}

#|( C<GET /credits>. Current credit balance. Requires a key. )
method get-credits(--> OpenRouter::API::Result::Credits:D) {
	self!require-auth('get-credits');
	my $data = self._request(:path</credits>);
	OpenRouter::API::Result::Credits.new(:data($data<data> // %()));
}

#|( C<GET /activity>. Daily spending / token rollup for the last 30
    UTC days, one row per (date × model × endpoint × provider).
    Filterable by single date, API-key hash, or organisation user
    ID. REQUIRES A MANAGEMENT KEY — the regular inference key
    returns 401/403 here; the wrapper translates that into a
    specific error pointing at the settings page. )
method get-activity(
	Str :$date,
	Str :$api-key-hash,
	Str :$user-id,
	--> List
) {
	self!require-auth('get-activity');

	my %query;
	%query<date>         = $date         if $date.defined         && $date.chars;
	%query<api_key_hash> = $api-key-hash if $api-key-hash.defined && $api-key-hash.chars;
	%query<user_id>      = $user-id      if $user-id.defined      && $user-id.chars;

	my $data;
	try {
		$data = self._request(:path</activity>, :%query);
		CATCH {
			when .message ~~ / 'HTTP 401' | 'HTTP 403' / {
				die qq:to/MSG/.chomp;
					OpenRouter::API: /activity requires a MANAGEMENT key, not a regular inference key.
					Generate one at https://openrouter.ai/settings/keys and set it as :api-key or OPENROUTER_API_KEY.
					MSG
			}
		}
	}
	($data<data> // []).map({
		OpenRouter::API::Result::ActivityRow.new(:data($_));
	}).List;
}

#|( C<GET /generation>. Post-hoc metadata for a single call — cost,
    tokens, latency, finish reason, routed provider. See also
    C<get-generation-content> for the stored prompt + completion
    text. Requires a key.

    Accepts either a Str gen-id (C<"gen-XXXX">) or any object that
    exposes a C<.generation-id> method — including
    L<LLM::Chat::Backend::Response::OpenRouter>. The second signature
    is duck-typed, so there's no hard dep on LLM::Chat. )
multi method get-generation(
	Str:D $id,
	--> OpenRouter::API::Result::Generation:D
) {
	self!require-auth('get-generation');
	my $data = self._request(:path</generation>, :query(%( id => $id )));
	OpenRouter::API::Result::Generation.new(:data($data<data> // %()));
}

multi method get-generation(
	$r where *.can('generation-id'),
	--> OpenRouter::API::Result::Generation:D
) {
	my $id = $r.generation-id;
	die "OpenRouter::API: passed object has no generation-id (got Nil)"
		unless $id.defined && $id.chars;
	self.get-generation($id);
}

#|( C<GET /generation/content>. Returns the stored prompt + completion
    text. Only populated when request logging is enabled on the
    account — otherwise the endpoint returns empty strings.

    Combines with the metadata from C</generation> into a single
    C<Generation> object: C<.prompt-text>, C<.completion-text>, and
    C<.reasoning-text> become available alongside all the usual
    cost / latency accessors. Requires a key. Accepts either a Str
    gen-id or a duck-typed object with C<.generation-id>. )
multi method get-generation-content(
	Str:D $id,
	--> OpenRouter::API::Result::Generation:D
) {
	self!require-auth('get-generation-content');
	my $meta    = self._request(:path</generation>,         :query(%( id => $id )));
	my $content = self._request(:path</generation/content>, :query(%( id => $id )));
	OpenRouter::API::Result::Generation.new(
		:data($meta<data>       // %()),
		:content($content<data> // %()),
	);
}

multi method get-generation-content(
	$r where *.can('generation-id'),
	--> OpenRouter::API::Result::Generation:D
) {
	my $id = $r.generation-id;
	die "OpenRouter::API: passed object has no generation-id (got Nil)"
		unless $id.defined && $id.chars;
	self.get-generation-content($id);
}

# --- filter helpers --------------------------------------------------

#|( Accept a List[Str] or a comma-joined Str for the capability
    filters; always emit the comma-joined shape OpenRouter wants
    in the query string. )
method !join-filter($v --> Str) {
	return $v.list.join(',') if $v ~~ Positional;
	return $v.Str;
}

#|( Client-side filtered search over the (optionally cached) model
    catalogue. Fetches via C<get-models>, then filters each entry
    with C<OpenRouter::API::Filter::matches>. Pass any combination
    of keyword / author / cost / context / capability filters —
    empty / undefined parameters are no-ops.

    The server-side C<category> / C<supported_parameters> /
    C<output_modalities> filters are forwarded to narrow the fetch;
    the client-side filters (keyword, cost, context) run over the
    fetched list.

    Returns a C<List[Model]>. )
method search-models(
	Str  :$keyword,
	Str  :$author,
	Rat  :$max-input-cost,
	Rat  :$max-output-cost,
	Int  :$min-context-length,
	Bool :$supports-tool-use,
	Bool :$supports-vision,
	Bool :$supports-reasoning,
	Bool :$supports-structured-outputs,
	# server-side pre-filter forwards
	:$category,
	:$supported-parameters,
	:$output-modalities,
	Bool:D :$cache = $!cache,
	--> List
) {
	my @models = self.get-models(
		:$category,
		:$supported-parameters,
		:$output-modalities,
		:$cache,
	);
	@models.grep({
		OpenRouter::API::Filter::matches(
			$_,
			:$keyword,
			:$author,
			:$max-input-cost,
			:$max-output-cost,
			:$min-context-length,
			:$supports-tool-use,
			:$supports-vision,
			:$supports-reasoning,
			:$supports-structured-outputs,
		)
	}).List;
}
