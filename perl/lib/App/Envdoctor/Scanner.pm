package App::Envdoctor::Scanner;

# Core scanner: reconcile %ENV access in Perl source against .env definitions.
# Local-first — no network, values never printed.

use strict;
use warnings;
use File::Find ();
use File::Spec ();

our $VERSION = '0.1.0';

my @USAGE = ( qr/\$ENV\{\s*["']?([A-Za-z_]\w*)["']?\s*\}/ );

sub _blank {
    my $s = shift;
    $s =~ s/[^\n]/ /g;
    return $s;
}

sub strip_noise {
    my ($code) = @_;
    # POD blocks: =word ... =cut
    $code =~ s/(^=\w+.*?^=cut[^\n]*)/_blank($1)/gems;
    # line comments
    $code =~ s/(#[^\n]*)/_blank($1)/ge;
    return $code;
}

sub scan_source {
    my ( $path, $content ) = @_;
    my $text = strip_noise($content);
    my %used;
    for my $re (@USAGE) {
        while ( $text =~ /$re/g ) {
            my $name  = $1;
            my $start = pos($text) - length($&);
            next if exists $used{$name};
            my $pre = substr( $text, 0, $start );
            my $line = ( $pre =~ tr/\n// ) + 1;
            $used{$name} = { file => $path, line => $line };
        }
    }
    return \%used;
}

sub parse_env {
    my ( $path, $content ) = @_;
    my %def;
    my $i = 0;
    for my $raw ( split /\n/, $content, -1 ) {
        $i++;
        my $t = $raw;
        $t =~ s/^\s+|\s+$//g;
        next if $t eq '' || $t =~ /^#/;
        if ( $raw =~ /^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=/ ) {
            $def{$1} //= { file => $path, line => $i };
        }
    }
    return \%def;
}

sub _read {
    my ($file) = @_;
    open my $fh, '<', $file or die "cannot read $file: $!";
    local $/;
    my $data = <$fh>;
    close $fh;
    return $data;
}

sub _rel {
    my ( $root, $path ) = @_;
    return File::Spec->abs2rel( $path, $root );
}

sub _find_files {
    my ( $root, $want ) = @_;
    my @out;
    File::Find::find(
        sub {
            return unless -f $_;
            my $full = $File::Find::name;
            return if $full =~ m{/(?:\.git|blib|node_modules)/};
            my $name = $_;
            if ( $want eq 'env' ) {
                push @out, $full
                    if $name eq '.env'
                    || ( $name =~ /^\.env\./ && $name !~ /\.example$/ );
            }
            elsif ( $name =~ /\.p[lm]$/ ) {
                push @out, $full;
            }
        },
        $root
    );
    return sort @out;
}

sub scan {
    my ($root) = @_;
    my ( %def, %used );

    for my $f ( _find_files( $root, 'env' ) ) {
        my $d = parse_env( _rel( $root, $f ), _read($f) );
        $def{$_} //= $d->{$_} for keys %$d;
    }
    for my $f ( _find_files( $root, 'perl' ) ) {
        my $u = scan_source( _rel( $root, $f ), _read($f) );
        $used{$_} //= $u->{$_} for keys %$u;
    }

    my @findings;
    for my $name ( sort keys %used ) {
        next if exists $def{$name};
        push @findings,
            {
            rule     => 'undefined-in-source',
            severity => 'error',
            name     => $name,
            message  => 'used in source code but not defined in any environment file',
            origin   => $used{$name},
            };
    }
    for my $name ( sort keys %def ) {
        next if exists $used{$name};
        push @findings,
            {
            rule     => 'unused',
            severity => 'warning',
            name     => $name,
            message  => 'defined but never referenced in source',
            origin   => $def{$name},
            };
    }
    return \@findings;
}

1;
