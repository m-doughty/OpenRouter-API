=begin pod

=head1 NAME

LiveKey - xt/ test helper for resolving OpenRouter credentials

=head1 SYNOPSIS

=begin code :lang<raku>

use lib 'lib', 'xt';
use LiveKey;

sub skip-without-key {
    my $key = resolve-api-key;
    unless $key {
        plan :skip-all<no inference key — set OPENROUTER_API_KEY or write .openrouter-api-key at the module root>;
        exit 0;
    }
    $key;
}

=end code

=head1 DESCRIPTION

Resolves a credential from the first source that produces a non-empty
string, in order:

=item C<%*ENV> value for the named variable
=item a file at C<<module-root>/<filename>>, trimmed

For the standard inference key, that's C<OPENROUTER_API_KEY> →
C<.openrouter-api-key>; for the management key, it's
C<OPENROUTER_MANAGEMENT_KEY> → C<.openrouter-management-key>. Both
files are listed in C<.gitignore>.

Returns C<Str> (empty string if nothing resolved — callers check with
C<.chars>). Pure — no network, no mutation.

=end pod

unit module LiveKey;

#|( Resolve the standard OR inference key from C<OPENROUTER_API_KEY>
    or the C<.openrouter-api-key> file at the module root. )
our sub resolve-api-key(--> Str) is export {
	resolve-credential(
		env-name  => 'OPENROUTER_API_KEY',
		file-name => '.openrouter-api-key',
	);
}

#|( Resolve the management-key variant. )
our sub resolve-management-key(--> Str) is export {
	resolve-credential(
		env-name  => 'OPENROUTER_MANAGEMENT_KEY',
		file-name => '.openrouter-management-key',
	);
}

#|( Env first, then the file at the module root. The module root is
    the parent of the directory this helper lives in — i.e. the
    parent of C<xt/>. Using C<$?FILE> rather than C<$*PROGRAM> so
    the lookup works regardless of what cwd the test was invoked
    from. Empty string when neither source yielded anything. )
sub resolve-credential(Str:D :$env-name, Str:D :$file-name --> Str) {
	my $env = %*ENV{$env-name};
	return $env if $env.defined && $env.chars;

	my $root = $?FILE.IO.parent.parent;  # .../xt/LiveKey.rakumod → .../
	my $path = $root.add($file-name);
	return '' unless $path.e;

	my $contents = $path.slurp.trim;
	return $contents if $contents.chars;
	'';
}
