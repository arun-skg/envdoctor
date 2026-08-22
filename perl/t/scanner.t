use strict;
use warnings;
use Test::More tests => 6;
use File::Temp ();
use File::Spec ();
use FindBin ();
use lib "$FindBin::Bin/../lib";
use App::Envdoctor::Scanner;

my $src = <<'PERL';
# $ENV{COMMENTED}
my $db = $ENV{DB_URL};
my $port = $ENV{'PORT'};
=pod
$ENV{BLOCK_IGNORED}
=cut
my $host = $ENV{"HOST"};
PERL

my $used = App::Envdoctor::Scanner::scan_source( 'config.pl', $src );
is_deeply( [ sort keys %$used ], [qw(DB_URL HOST PORT)], 'detects $ENV{...} forms' );
ok( !exists $used->{COMMENTED},     'ignores line comments' );
ok( !exists $used->{BLOCK_IGNORED}, 'ignores POD blocks' );

my $dir = File::Temp->newdir;
open my $e, '>', File::Spec->catfile( "$dir", '.env' ) or die $!;
print {$e} "DB_URL=x\nUNUSED_KEY=1\n";
close $e;
open my $s, '>', File::Spec->catfile( "$dir", 'app.pl' ) or die $!;
print {$s} "\$ENV{DB_URL};\n\$ENV{NEW_FLAG};\n";
close $s;

my $findings = App::Envdoctor::Scanner::scan("$dir");
my %err  = map { $_->{name} => 1 } grep { $_->{severity} eq 'error' } @$findings;
my %warn = map { $_->{name} => 1 } grep { $_->{severity} eq 'warning' } @$findings;
ok( $err{NEW_FLAG},    'NEW_FLAG reported as error' );
ok( $warn{UNUSED_KEY}, 'UNUSED_KEY reported as warning' );
ok( !$err{DB_URL} && !$warn{DB_URL}, 'DB_URL reconciled' );
