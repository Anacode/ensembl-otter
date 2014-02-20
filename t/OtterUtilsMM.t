#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::Otter::Accessions;

use Test::More;

my $module;
BEGIN {
    $module = 'Bio::Otter::Utils::MM';
    use_ok($module);
}

critic_module_ok($module);

my $mm = $module->new;
isa_ok($mm, $module);

my @valid_accs = qw(AK122591.2 AK122591);
my @invalid_accs = qw(AK122591.1 XYZ123456 ERS000123 NM_001142769.1); # one old SV, one nonsense, one SRA, one ?

my $results = $mm->get_accession_types([@valid_accs, @invalid_accs]);
is(ref($results), 'HASH', 'results hash');

foreach my $valid ( @valid_accs ) {
    my $at = $results->{$valid};
    ok($at, "$valid: have result");
    ok($at->[4], "$valid: has taxon_id");
    note("\ttaxon_id:\t", $at->[4]);
    note("\ttitle:\t\t", $at->[5]);
}

foreach my $invalid ( @invalid_accs ) {
    my $at = $results->{$invalid};
    ok(not($at), "$invalid: no result");
}

# Singleton
my $acc = $valid_accs[1];
my $s_results = $mm->get_accession_types([$acc]);
is(ref($s_results), 'HASH', 's_results hash');
ok($s_results->{$acc}, 'result is for singleton acc');

# Empty
my $e_results = $mm->get_accession_types([]);
is(ref($e_results), 'HASH', 'e_results hash');
ok(not(%$e_results), 'result is empty');

# New central list
my $ta_factory = Test::Otter::Accessions->new;
my $ta_acc_specs = $ta_factory->accessions;
my @ta_accs = map { $_->{query} } @$ta_acc_specs;
my $ta_results = $mm->get_accession_types(\@ta_accs);
is(ref($ta_results), 'HASH', 'ta_results hash');

foreach my $ta_acc_spec (@$ta_acc_specs) {
    my $query = $ta_acc_spec->{query};
    subtest $query => sub {
        my $result = $ta_results->{$query};
        if ($ta_acc_spec->{evi_type}) {
            my ($evi_type, $acc_sv, $source_db) = @$result;
            is($acc_sv,    $ta_acc_spec->{acc_sv},    'acc_sv');
            is($evi_type,  $ta_acc_spec->{evi_type},  'evi_type');
            is($source_db, $ta_acc_spec->{source_db}, 'source_db');
        } else {
            is($result, undef, 'no result');
        }
        done_testing;
    };
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF