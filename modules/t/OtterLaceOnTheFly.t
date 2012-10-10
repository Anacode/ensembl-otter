#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

use File::Temp;

use FindBin qw($Bin);
use lib "$Bin/lib";
use OtterTest::Client;

use Bio::Otter::Lace::AccessionTypeCache;
use Bio::Otter::Lace::DB;
use Bio::Otter::Lace::Exonerate;
use Bio::Otter::LocalServer;
use Bio::Otter::ServerAction::Region;

use Hum::ClipboardUtils;
use Hum::FastaFileIO;

my @modules;

BEGIN {

    @modules = qw(
        Bio::Otter::Lace::OnTheFly
        Bio::Otter::Lace::OnTheFly::Aligner
        Bio::Otter::Lace::OnTheFly::Aligner::Genomic
        Bio::Otter::Lace::OnTheFly::Aligner::Transcript
        Bio::Otter::Lace::OnTheFly::FastaFile
        Bio::Otter::Lace::OnTheFly::Genomic
        Bio::Otter::Lace::OnTheFly::QueryValidator
        Bio::Otter::Lace::OnTheFly::ResultSet
        Bio::Otter::Lace::OnTheFly::TargetSeq
        Bio::Otter::Lace::OnTheFly::Transcript
    );

    foreach my $module ( @modules ) {
        use_ok($module);
    }
}

foreach my $module ( @modules ) {
    critic_module_ok($module);
}

my $path = "$Bin/etc/align";

my @tests = (
    {
        name        => 'test_clone vs. test_query',
        target_path => "${path}/test_clone.fa",
        query_path  => "${path}/test_query.fa",
        query_ids   => [qw(BC018923.fwd BC018923.rev)],
    },
    {
        name        => 'AL139092 vs. BC018923',
        target_path => "${path}/AL139092.12.fasta",
        query_path  => "${path}/BC018923.fasta",
        query_ids   => [qw(ENA|BC018923|BC018923.2)],
    },
    {
        name        => 'AL139092 vs. BI831275',
        target_path => "${path}/AL139092.12.fasta",
        query_path  => "${path}/BI831275.fasta",
        query_ids   => [qw(ENA|BI831275|BI831275.1)],
    },
    {
        name        => 'AL133351 vs. BG212959.1',
        target_path => "${path}/AL133351.34.fasta",
        query_path  => "${path}/BG212959.1.fa",
        query_ids   => [qw(BG212959.1)],
    },
    {
        name        => 'AL139092 vs. protein Q96S55',
        target_path => "${path}/AL139092.12.fasta",
        query_path  => "${path}/Q96S55.fasta",
        query_ids   => [qw(sp|Q96S55|WRIP1_HUMAN)],
        type        => 'Test_Protein',
    },
    {
        name        => 'test_clone vs. protein Q96S55',
        target_path => "${path}/test_clone.fa",
        query_path  => "${path}/Q96S55.fasta",
        query_ids   => [qw(sp|Q96S55|WRIP1_HUMAN)],
        type        => 'Test_Protein',
    },
    {
        name        => 'AL133351 vs. protein Q8VHQ0.1',
        target_path => "${path}/AL133351.34.fasta",
        query_path  => "${path}/Q8VHQ0.fasta",
        query_ids   => [qw(Q8VHQ0.1)],
        type        => 'Test_Protein',
    },

    );

my @todo_tests = (
    );

my %species_tests = (
    human => [
        { title => 'AL133351.34', type => 'chr6-18', start => 2864371, end => 3037940, },
    ],
    );

foreach my $test ( @tests ) {
    run_test($test);
}

TODO: {
    local $TODO = "Protein handling not yet compatible for frameshift and split codon";

    foreach my $test ( @todo_tests ) {
        run_test($test);
    }
}

local $ENV{DOCUMENT_ROOT} = '/nfs/WWWdev/SANGER_docs/htdocs';
my $tmp_dir = File::Temp->newdir;
my $at_cache = setup_accession_type_cache($tmp_dir->dirname);

while (my ($species, $regions) = each %species_tests) {
    note("Live tests for: $species");
    my $local_server = Bio::Otter::LocalServer->new({dataset => $species});
    foreach my $region ( @$regions ) {
        run_region($local_server, $region, $at_cache);
    }
}

done_testing;

sub run_test {
    my $test = shift;

    note 'Test: ', $test->{name};

    my $target = new_ok('Bio::Otter::Lace::OnTheFly::TargetSeq' =>
                        [ full_seq => Hum::FastaFileIO->new_DNA_IO($test->{target_path})->read_one_sequence ]
        );

    my @seqs = ( Hum::FastaFileIO->new_DNA_IO($test->{query_path})->read_all_sequences );

    my $aligner = new_ok( 'Bio::Otter::Lace::OnTheFly::Aligner::Genomic' => [{
        type   => $test->{type} || 'Test_EST',
        seqs   => \@seqs,
        target => $target,
                                                                             }]);

    my $result_set = $aligner->run;
    isa_ok($result_set, 'Bio::Otter::Lace::OnTheFly::ResultSet');

    my @qids = sort $result_set->query_ids;
    is(scalar(@qids), scalar(@{$test->{query_ids}}), 'n(query_ids)');
    is_deeply(\@qids, $test->{query_ids}, 'query_ids');

    my @gapped_alignments =  map { @{$result_set->by_query_id($_)} } @qids;
    my @new_features;
    foreach my $ga ( @gapped_alignments ) {
        push @new_features, $ga->ensembl_features;
        note $ga->query_id, ': QS ', $ga->query_strand, ', TS ', $ga->target_strand, ', GO ', $ga->gene_orientation;
    }
    @new_features = sort feature_sort @new_features;
    note("n(new_features): ", scalar(@new_features));

    # Do it the old way, for comparison

    my $target_seq = $target->target_seq;
    my $dna_str = $target_seq->sequence_string;
    $dna_str =~ s/-/N/g;
    my $target_bio_seq = Bio::Seq->new( -id => $target_seq->name, -seq => $dna_str, -alphabet => 'dna');

    my $exonerate = Bio::Otter::Lace::Exonerate->new;
    $exonerate->initialise($test->{query_path});
    $exonerate->bestn(1);
    $exonerate->max_intron_length(200000);
    $exonerate->score(100);
    $exonerate->dnahsp(120);

    $exonerate->query_type('protein') if $test->{type} and $test->{type} =~ /protein/i;

    my $output = $exonerate->run_exonerate($target_bio_seq, $target_bio_seq);
    my @output_features = sort feature_sort @$output;

    note("n(output_features): ", scalar(@output_features));
    is(scalar @new_features, scalar@output_features, 'n(new_features)');
    foreach my $n ( 0 .. scalar(@new_features) - 1 ) {
        subtest "Feature $n" => sub {
            foreach my $member (
                qw{
                seqname
                start
                end
                strand

                hseqname
                hstart
                hend
                hstrand

                cigar_string

                percent_id
              }
                # Not implemented yet:
                # hcoverage
                # score
                )
            {
                is($new_features[$n]->$member(), $output_features[$n]->$member(), $member);
            }
            done_testing;
        }
    }

}

sub run_region {
    my ($local_server, $region, $at_cache) = @_;
    note("  Region: ", $region->{title});
    my $sa_region = Bio::Otter::ServerAction::Region->new_with_slice($local_server, $region);

    my $dna = $sa_region->get_assembly_dna;
    my $target_seq = Hum::Sequence::DNA->new;
    $target_seq->name($region->{title});
    $target_seq->sequence_string($dna);

    my $genes = $sa_region->get_region->genes;
    foreach my $gene (@$genes) {
        note("    Gene: ", $gene->stable_id);
        my $transcripts = $gene->get_all_Transcripts;
        foreach my $ts (@$transcripts) {
            note("      Transcript: ", $ts->stable_id);
            my $evi_list = $ts->evidence_list;
            my $q_validator = get_query_validator($at_cache, $evi_list);
            note("        ", join(',', map{ $_->name } @{$q_validator->confirmed_seqs}));
        }
    }
}

sub get_query_validator {
    my ($at_cache, $evi_list) = @_;
    my @evi_names = map { Hum::ClipboardUtils::accessions_from_text($_->name) } @$evi_list;
    my $q_validator = Bio::Otter::Lace::OnTheFly::QueryValidator->new(
        accession_type_cache => $at_cache,
        accessions           => \@evi_names,
        problem_report_cb    => sub {
            my ($self, $msgs) = @_;
            map { diag("QV ", $_, ": ", $msgs->{$_}) if $msgs->{$_} } keys %$msgs;
        },
        long_query_cb        => sub { diag("QV long q: ", shift, "(", shift, ")"); },
        );
    return $q_validator;
}

sub setup_accession_type_cache {
    my $tmp_dir = shift;
    my $test_client = OtterTest::Client->new;
    my $test_db = Bio::Otter::Lace::DB->new($tmp_dir);
    $at_cache = Bio::Otter::Lace::AccessionTypeCache->new;
    $at_cache->Client($test_client);
    $at_cache->DB($test_db);
    return $at_cache;
}

sub feature_sort {
    return
        $a->hseqname cmp $b->hseqname
        ||
        $a->start    cmp $b->start
        ||
        $a->end      cmp $b->end;
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
