#!/usr/bin/env perl

use strictures 2;
use 5.020;
use Cwd;
use File::Temp qw/tempdir/;
use Mojo::SQLite;
use Mojo::UserAgent;
use experimental 'postderef';
use constant DB_FILE => 'test.db';

my $sql = get_sql(DB_FILE);
my @unprocessed = map $_->{url}, $sql->db
    ->query('SELECT * FROM dists WHERE processed = 0 ORDER BY url')
        ->hashes->@*;

my @errors;
$SIG{INT} = sub { exit };
END { show_errors(@errors) };

for ( 0 .. $#unprocessed ) {
    my $d = $unprocessed[$_];
    my ( $n, $out_of ) = ( $_+1, scalar(@unprocessed) );
    say "Doing $d ($n out of $out_of)";
    process($d, \@errors);
    $sql->db->query('UPDATE dists SET processed = 1 WHERE url = ?', $d);
    say "Done";
}
say "Finished all";

exit;
##########################################################

sub show_errors {
    my @errors = @_;
    say "\n\nFound " . @errors . " errors:";
    say for @errors;
    exit;
}

sub process {
    my ( $url, $errors ) = @_;
    my $cwd = cwd;
    my $dir = tempdir CLEANUP => 1;

    chdir $dir;
        say `git clone -q $url .`;
        my $is_inc = `grep -iR '\\\@\\*INC' .`;
    chdir $cwd;

    say $is_inc;
    push @$errors, $url if $is_inc;
}

sub get_sql {
    my $db_file = shift;

    my $deploy = not -e $db_file;

    my $sql = Mojo::SQLite->new("sqlite:$db_file");
    if ( $deploy ) {
        $sql->db->query('
            CREATE TABLE dists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT,
            processed BOOL
        )');

        my @dists = Mojo::UserAgent->new->get('http://modules.perl6.org')
            ->res->dom->find('a.github')->map(sub{$_->{href}})->@*;

        say "Found " . @dists . " dists";
        for ( @dists ) {
            $sql->db->query(
                'INSERT INTO dists (url, processed) VALUES ( ? , ? )',
                $_, 0,
            );
        }
    }

    return $sql;
}
