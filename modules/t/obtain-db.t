#! /usr/bin/env perl

use strict;
use warnings;

use Sys::Hostname 'hostname';
use Test::More;
use Net::Netrc;
use DBI;
use YAML 'Dump'; # for diag


=head1 NAME

obtain-db.t - see that we can talk to database servers

=head1 DESCRIPTION

This test connects to database servers.  It makes no lasting changes,
but in some cases it must satisfy itself that it has a read-only or
read-write connection.

=head2 Aims

=over 4

=item *

Exercise all the supported methods of connecting.  Incomplete.

=item *

Ensure all routes lead to the same place.  Incomplete.

=item *

Ensure all configured databases are available.  Incomplete.

=item *

For read-write databases, check the transaction isolation mode.
Later!

=item *

Check locales, collation orders, timezones, idle-disconnect settings,
error raising...  later!

=item *

Check Ensembl schema version numbers.  Later.

=back

Some of these aims may be better split out to a combination of
database enumeration module & another test script.


=head1 CONNECTION ROUTES

There are several ways to obtain database connection parameters, some
of which would work outside the firewall.  However there is no support
for connecting from outside so we skip the tests in this case.

There are also at least two classes of code making these connections:
ensembl-otter and ensembl-pipeline.

=head2 By commandline argument

Some scripts take L<DBI>-like connection parameters: host, port, user,
dbname.

Some also take an explicit password.  This script needs a password
file on disk and ignores the "explicit password" variation.

=head2 Direct access to Otter Data directory

Use the Otter Server's data files to reach databases.

=head2 Via Otter Server

Call the Otter Server as a client and ask for datasets.

=cut


sub main {
    my $host = hostname(); # not FQDN on my deskpro
    unless (hostname =~ /\.sanger\.ac\.uk$/ || -d "/software/anacode" || $ENV{WTSI_INTERNAL}) {
        plan skip_all => "Direct database access not expected to work from $host - set WTSI_INTERNAL=1 to try";
        # it exits
    }

    plan tests => 6;

    cmdline_tt({qw{ host otterlive database loutre_human }},
               [ 'loutre_human by args', 'human', 'ensembl:loutre' ]);

    cmdline_tt({qw{ host otterpipe1 database pipe_human }},
               [ 'pipe_human by args', 'human', 'ensembl:pipe' ]);

}


sub cmdline_tt {
    my ($args, $check) = @_;

    my $dbh = eval { netrc_dbh(%$args) } || "perl_err=$@";
    check_dbh($dbh, @$check);
}


# $dbh: can proceed with a DBI handle or a problem string
sub check_dbh {
    my ($dbh, $what, $species_want, $schema_want) = @_;

  SKIP: {
        my $ping;
        $ping = "not a dbh: $dbh" unless ref($dbh);
        $ping ||= $dbh->ping ? 'ping' : 'broken';
        is($ping, 'ping', "$what: ping")
          or skip("no database handle for $what" => 2);

        my $schema_got = guess_schema($dbh);
        is($schema_got, $schema_want, "$what: schema type");

        my $species_got = rowhash($dbh, q{select * from meta where meta_key = 'species.common_name'});
        is($species_got->{'meta_value'}, $species_want, "$what: species")
          || diag(Dump($species_got));
    }
}


### Utility functions - could be more useful elsewhere

sub netrc_dbh {
    my %args = @_;

    my $ref = Net::Netrc->lookup($args{'host'})
      or die "No entry found in ~/.netrc for host $args{'host'}";
    @args{qw{ user pass port }} = ($ref->login, $ref->password, $ref->account);

    my $dsn = "DBI:mysql:". join ';', map {"$_=$args{$_}"} qw( database host port );
    return DBI->connect($dsn, @args{qw{ user pass }}, { 'RaiseError' => 1 });
}


sub rowhash {
    my ($dbh, $sql) = @_;
    return eval {
        local $dbh->{PrintError} = 0;
        $dbh->selectrow_hashref($sql)
          || { DBI_err => $dbh->err };
    } || { perl_err => $@ };
}

sub fields_string {
    my ($rowhash) = @_;
    return join ':', map { lc($_) } sort keys %$rowhash;
}

sub field_exist {
    my ($want, $rowhash) = @_;
    return grep { lc($_) eq $want } keys %$rowhash;
}

sub guess_schema {
    my ($dbh) = @_;
    my @type;

    my $meta = rowhash($dbh, 'select * from meta');
    my $sr = rowhash($dbh, 'select * from seq_region limit 1');
    push @type, 'ensembl' if field_exist(coord_system_id => $sr)
      && fields_string($meta) eq 'meta_id:meta_key:meta_value:species_id';

    my $ga = rowhash
      ($dbh, 'select * from gene g
 join gene_author ga using (gene_id)
 join author using (author_id)
 limit 1');
    push @type, 'loutre' if field_exist(author_name => $ga);

    my $iia = rowhash
      ($dbh, 'select * from job j
 join input_id_analysis iia using (input_id, analysis_id)
 join analysis a using (analysis_id)
 limit 1');
    push @type, 'pipe' if field_exist(runhost => $iia);

    my $proj_acc = rowhash
      ($dbh, 'select * from sequence
 join project_dump using (seq_id)
 join project_acc using (sanger_id)
 limit 1');
    push @type, 'submissions' if field_exist(htgs_phase => $proj_acc);

    return join ':', sort @type;
}


main();