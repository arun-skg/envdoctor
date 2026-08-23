use strict;
use warnings;
use Test::More tests => 34;
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

# duplicates + public-prefix
my $dir2 = File::Temp->newdir;
open my $e2, '>', File::Spec->catfile( "$dir2", '.env' ) or die $!;
print {$e2}
    "DUP_KEY=1\nSINGLE_KEY=2\nDUP_KEY=3\nNEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=y\nAPI_KEY=z\nPUBLIC_KEY=k\n";
close $e2;
open my $s2, '>', File::Spec->catfile( "$dir2", 'app.pl' ) or die $!;
print {$s2}
    "\$ENV{DUP_KEY};\n\$ENV{SINGLE_KEY};\n\$ENV{NEXT_PUBLIC_API_KEY};\n\$ENV{PUBLIC_URL};\n\$ENV{API_KEY};\n\$ENV{PUBLIC_KEY};\n";
close $s2;

my $f2 = App::Envdoctor::Scanner::scan("$dir2");
my ($dup) = grep { $_->{rule} eq 'duplicates' && $_->{name} eq 'DUP_KEY' } @$f2;
ok( $dup, 'DUP_KEY reported as duplicates' );
is( $dup->{severity}, 'error', 'duplicates is an error' );
is( $dup->{message}, 'defined 2 times in the same file (lines 1, 3)',
    'duplicates message lists lines' );
ok( !( grep { $_->{rule} eq 'duplicates' && $_->{name} eq 'SINGLE_KEY' } @$f2 ),
    'single-definition key not reported as duplicate' );

my %pub = map { $_->{name} => 1 } grep { $_->{rule} eq 'public-prefix' } @$f2;
ok( $pub{NEXT_PUBLIC_API_KEY}, 'NEXT_PUBLIC_API_KEY flagged as public-prefix' );
ok( !$pub{PUBLIC_URL}, 'PUBLIC_URL not flagged' );
ok( !$pub{API_KEY}, 'bare API_KEY not flagged' );
ok( !$pub{PUBLIC_KEY}, 'PUBLIC_KEY not flagged (bare KEY excluded)' );

# ---- env labels, values never leak ------------------------------------------
is( App::Envdoctor::Scanner::env_label('.env'),                  'default',    'label .env' );
is( App::Envdoctor::Scanner::env_label('.env.local'),            'local',      'label local' );
is( App::Envdoctor::Scanner::env_label('.env.production.local'), 'production', 'label strips .local' );

# ---- weak-secret + typo + no value leakage ----------------------------------
my $dir3 = File::Temp->newdir;
open my $e3, '>', File::Spec->catfile( "$dir3", '.env' ) or die $!;
print {$e3} "API_KEY=changeme\nSTRONG_TOKEN=a7Kf93ZqL0\nDATABASE_URL=postgres://localhost\n";
close $e3;
open my $s3, '>', File::Spec->catfile( "$dir3", 'app.pl' ) or die $!;
print {$s3}
    "\$ENV{API_KEY};\n\$ENV{STRONG_TOKEN};\n\$ENV{DATABASE_URL};\n\$ENV{DATBASE_URL};\n";
close $s3;

my $f3 = App::Envdoctor::Scanner::scan("$dir3");
my ($weak) = grep { $_->{rule} eq 'weak-secret' && $_->{name} eq 'API_KEY' } @$f3;
ok( $weak, 'API_KEY flagged as weak-secret' );
is( $weak->{severity}, 'warning', 'weak-secret is a warning' );
ok( !( grep { $_->{rule} eq 'weak-secret' && $_->{name} eq 'STRONG_TOKEN' } @$f3 ),
    'strong secret not flagged' );
my ($typo) = grep { $_->{rule} eq 'typo' && $_->{name} eq 'DATBASE_URL' } @$f3;
ok( $typo, 'DATBASE_URL flagged as typo' );
is( $typo->{message}, '"DATBASE_URL" is not defined; did you mean "DATABASE_URL"?',
    'typo message suggests DATABASE_URL' );
my $blob3 = join "\n", map { "$_->{message}" } @$f3;
ok( $blob3 !~ /changeme/ && $blob3 !~ /postgres/ && $blob3 !~ /a7Kf93ZqL0/,
    'no value strings leak into findings' );

# ---- environment-diff + type-mismatch ---------------------------------------
my $dir4 = File::Temp->newdir;
open my $ea, '>', File::Spec->catfile( "$dir4", '.env' ) or die $!;
print {$ea} "PORT=8080\nONLY_DEFAULT=1\n";
close $ea;
open my $eb, '>', File::Spec->catfile( "$dir4", '.env.production' ) or die $!;
print {$eb} "PORT=high\n";
close $eb;
open my $s4, '>', File::Spec->catfile( "$dir4", 'app.pl' ) or die $!;
print {$s4} "\$ENV{PORT};\n\$ENV{ONLY_DEFAULT};\n";
close $s4;

my $f4 = App::Envdoctor::Scanner::scan("$dir4");
my ($tm) = grep { $_->{rule} eq 'type-mismatch' && $_->{name} eq 'PORT' } @$f4;
ok( $tm, 'PORT flagged as type-mismatch (integer vs string)' );
is( $tm->{severity}, 'error', 'type-mismatch is an error' );
my ($ed) = grep { $_->{rule} eq 'environment-diff' && $_->{name} eq 'ONLY_DEFAULT' } @$f4;
ok( $ed, 'ONLY_DEFAULT flagged as environment-diff' );
is( $ed->{message}, 'defined in default but missing in production',
    'environment-diff lists present/absent labels' );

# two integers across envs -> no type-mismatch
my $dir5 = File::Temp->newdir;
open my $ec, '>', File::Spec->catfile( "$dir5", '.env' ) or die $!;
print {$ec} "PORT=8080\n";
close $ec;
open my $edd, '>', File::Spec->catfile( "$dir5", '.env.production' ) or die $!;
print {$edd} "PORT=9090\n";
close $edd;
open my $s5, '>', File::Spec->catfile( "$dir5", 'app.pl' ) or die $!;
print {$s5} "\$ENV{PORT};\n";
close $s5;
my $f5 = App::Envdoctor::Scanner::scan("$dir5");
ok( !( grep { $_->{rule} eq 'type-mismatch' } @$f5 ),
    'two integers across envs -> no type-mismatch' );

# diff + sync subcommands
{
    my $d2 = File::Temp->newdir;
    open my $e, '>', File::Spec->catfile( "$d2", '.env' ) or die $!;
    print {$e} "A=1\nB=2\n"; close $e;
    open my $p, '>', File::Spec->catfile( "$d2", '.env.production' ) or die $!;
    print {$p} "A=9\n"; close $p;

    my $diff = App::Envdoctor::Scanner::diff_labels( "$d2", 'default', 'production' );
    is_deeply( $diff->{onlyInA}, ['B'], 'diff onlyInA' );
    is_deeply( $diff->{onlyInB}, [],    'diff onlyInB' );
    is_deeply( $diff->{common},  ['A'], 'diff common' );

    my $dry = App::Envdoctor::Scanner::sync_labels( "$d2", 'default', 'production', 1 );
    is_deeply( $dry, ['B'], 'sync --dry-run reports B' );
    unlike( App::Envdoctor::Scanner::_read( File::Spec->catfile("$d2",'.env.production') ), qr/B=/, 'dry-run does not write' );

    App::Envdoctor::Scanner::sync_labels( "$d2", 'default', 'production', 0 );
    my $prod = App::Envdoctor::Scanner::_read( File::Spec->catfile("$d2",'.env.production') );
    ok( $prod =~ /B=\n/ && $prod =~ /A=9/ && $prod !~ /B=2/, 'sync appends B= without value' );
}
