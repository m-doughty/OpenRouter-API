[![Actions Status](https://github.com/m-doughty/OpenRouter-API/actions/workflows/test.yml/badge.svg)](https://github.com/m-doughty/OpenRouter-API/actions)

NAME
====

OpenRouter::API - Raku client for OpenRouter's non-inference REST API

SYNOPSIS
========

```raku
use OpenRouter::API;

# Reads OPENROUTER_API_KEY from the environment by default.
my $or = OpenRouter::API::Client.new;

# ----- model catalogue ---------------------------------------------

my @models = $or.get-models;
say @models.elems, " models available";

# search-models filters the cached catalogue entirely client-side
# (OpenRouter has no server-side keyword search).
my @candidates = $or.search-models(
    :keyword<claude>,
    :supports-tool-use,
    :min-context-length(200_000),
);

# Drill into a single model's per-provider endpoints — pricing,
# throughput, context, ZDR:
my @endpoints = $or.get-model-endpoints('anthropic', 'claude-opus-4-7');
say "cheapest: ", @endpoints.sort(*.price-per-input-token).head.provider-name;

# ----- spending ----------------------------------------------------

# Current credit balance.
say $or.get-credits.remaining, " USD left";

# Daily activity. REQUIRES A MANAGEMENT KEY (the regular inference
# key returns 401 here). Get one from
# https://openrouter.ai/settings/keys.
my @rows = $or.get-activity;
say @rows.elems, " activity rows over the last 30 days";

# Narrow by date / key / user:
my @today = $or.get-activity(:date<2026-04-24>);

# ----- per-call cost lookup ----------------------------------------

# Pass a Str gen-id...
my $gen = $or.get-generation('gen-abc123');

# ...or duck-type from any object with a .generation-id accessor —
# e.g. LLM::Chat::Backend::Response::OpenRouter, which exposes the
# gen-id directly on the Response.
use LLM::Chat::Backend::OpenRouter;
my $llm  = LLM::Chat::Backend::OpenRouter.new(
    api_key => %*ENV<OPENROUTER_API_KEY>,
    model   => 'anthropic/claude-opus-4-7',
);
my $resp = $llm.chat-completion(@messages);
# ...drain the supply...
my $details = $or.get-generation($resp);   # takes the Response directly

# /generation/content returns the stored prompt + completion text
# on top of the cost metadata — only populated when request logging
# is enabled on the OpenRouter account.
my $with-text = $or.get-generation-content($resp);
say $with-text.prompt-text;
say $with-text.completion-text;
```

DESCRIPTION
===========

OpenRouter::API wraps OpenRouter's REST surface for everything that isn't inference. Use it when you want to:

  * Browse the model catalogue (`get-models`, `search-models`, `count-models`, `get-user-models`).

  * Inspect which providers will actually serve a given model and at what price (`get-model-endpoints`, `get-providers`, `get-zdr-endpoints`).

  * Track spend: current balance (`get-credits`), daily rollups (`get-activity`), or individual call metadata (`get-generation` / `get-generation-content`).

Inference itself — `POST /chat/completions` — is deliberately out of scope. See [LLM::Chat::Backend::OpenRouter](LLM::Chat::Backend::OpenRouter) for that.

Conventions
-----------

### Auth

Pass `:api-key` to the constructor, or set `OPENROUTER_API_KEY` in the environment. Endpoints that require an API key die with a helpful message if none is configured. Endpoints that work unauthenticated (`/models`, `/models/count`, `/providers`, `/endpoints/zdr`) run without a key.

### Management vs inference keys

`/activity` uses a different key scope than the rest. OpenRouter issues *management* keys for account-level introspection endpoints; your usual inference key will come back 401/403 there. The wrapper normalises the error and points you at the settings page.

### Result types

Each endpoint returns a typed object with named accessors and derived helpers. When OpenRouter adds fields we haven't typed, `.raw` gives you the wire hash. Examples of the derived helpers:

  * `Model.cheapest-endpoint` — scans per-provider endpoints and returns the one with the lowest input-token price.

  * `Model.supports-tool-use`, `Model.supports-vision` — capability checks against the `supported_parameters` / `output_modalities` wire fields.

  * `ActivityRow.cost-per-1k-tokens` — derived from `.cost` / (`.prompt-tokens` + `.completion-tokens`).

### Caching

`search-models` routes through a 5-minute TTL cache on the full `/models` response. Filter calls against it are free after the first fetch. Disable with `:cache(False)` on the Client, or call `.clear-cache` to invalidate. Other endpoints are not cached — `/credits` and `/activity` need to be live every time.

### Attribution

Pass `:http-referer` / `:x-title` to the Client to forward OpenRouter's attribution headers on every call. These show up on the OpenRouter rankings page and in users' generation logs. Both are optional.

SEE ALSO
========

  * [https://openrouter.ai/docs/api-reference/overview](https://openrouter.ai/docs/api-reference/overview) - upstream API docs.

  * [https://openrouter.ai/openapi.json](https://openrouter.ai/openapi.json) - OpenAPI spec (the source of truth for wire shapes).

  * [LLM::Chat::Backend::OpenRouter](LLM::Chat::Backend::OpenRouter) - the inference-side OR backend in this monorepo.

AUTHOR
======

Matt Doughty

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

