package Bio::Otter::Lace::Slice;

use strict;
use warnings;

use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;

sub new {
    my( $pkg,
        $Client, # object
        $dsname, # e.g. 'human'
        $ssname, # e.g. 'chr20-03'

        $csname, # e.g. 'chromosome'
        $csver,  # e.g. 'Otter'
        $seqname,# e.g. '20'
        $start,  # in the given coordinate system
        $end,    # in the given coordinate system
    ) = @_;

    # chromosome:Otter:chr6-17:2666323:2834369:1


    my $self = {
        '_Client'   => $Client,
        '_dsname'   => $dsname,
        '_ssname'   => $ssname,

        '_csname'   => $csname,
        '_csver'    => $csver  || '',
        '_seqname'  => $seqname,
        '_start'    => $start,
        '_end'      => $end,
    };

    return bless $self, $pkg;
}

sub Client {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change Client" if defined($dummy);

    return $self->{_Client};
}

sub dsname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change dsname" if defined($dummy);

    return $self->{_dsname};
}

sub ssname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change ssname" if defined($dummy);

    return $self->{_ssname};
}


sub csname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change csname" if defined($dummy);

    return $self->{_csname};
}

sub csver {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change csver" if defined($dummy);

    return $self->{_csver};
}

sub seqname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change seqname" if defined($dummy);

    return $self->{_seqname};
}

sub start {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change start" if defined($dummy);

    return $self->{_start};
}

sub end {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change end" if defined($dummy);

    return $self->{_end};
}

sub length { ## no critic(Subroutines::ProhibitBuiltinHomonyms)
    my ( $self ) = @_;

    return $self->end() - $self->start() + 1;
}

sub name {
    my( $self ) = @_;

    return sprintf "%s_%d-%d",
        $self->ssname,
        $self->start,
        $self->end;
}


sub toHash {
    my ($self) = @_;

    my $hash = {
            'dataset' => $self->dsname(),
            'type'    => $self->ssname(),

            'cs'      => $self->csname(),
            'csver'   => $self->csver(),
            'name'    => $self->seqname(),
            'start'   => $self->start(),
            'end'     => $self->end(),
    };

    return $hash;
}

sub zmap_config_stanza {
    my ($self) = @_;

    my $hash = {
        'dataset'  => $self->dsname,
        'sequence' => $self->ssname,
        'csname'   => $self->csname,
        'csver'    => $self->csver,
        'start'    => $self->start,
        'end'      => $self->end,
    };

    return $hash;
}

sub create_detached_slice {
    my ($self) = @_;

    my $slice = Bio::EnsEMBL::Slice->new(
        -seq_region_name    => $self->ssname,
        -start              => $self->start,
        -end                => $self->end,
        -coord_system   => Bio::EnsEMBL::CoordSystem->new(
            -name           => $self->csname,
            -version        => $self->csver,
            -rank           => 2,
            -sequence_level => 0,
            -default        => 1,
        ),
    );
    return $slice;
}

# ----------------------------------------------------------------------------------


sub dna_ace_data {
    my ($self) = @_;

    my ($dna, @tiles) = split /\n/, $self->http_response_content('GET', 'get_assembly_dna');

    $dna = lc $dna;
    $dna =~ s/(.{60})/$1\n/g;

    my @feature_ace;
    my %seen_ctg = ( );
    my @ctg_ace = ( );

    for (@tiles) {

        my ($start, $end,
            $ctg_name, $ctg_start,
            $ctg_end, $ctg_strand, $ctg_length,
            ) = split /\t/;
        ($start, $end) = ($end, $start) if $ctg_strand == -1;

        my $strand_ace =
            $ctg_strand == -1 ? 'minus' : 'plus';
        my $feature_ace =
            sprintf qq{Feature "Genomic_canonical" %d %d %f "%s-%d-%d-%s"\n},
            $start, $end, 1.000, $ctg_name, $ctg_start, $ctg_end, $strand_ace;
        push @feature_ace, $feature_ace;

        unless ( $seen_ctg{$ctg_name} ) {
            $seen_ctg{$ctg_name} = 1;
            my $ctg_ace =
                sprintf qq{\nSequence "%s"\nLength %d\n}, $ctg_name, $ctg_length;
            push @ctg_ace, $ctg_ace;
        }

    }

    my $name = $self->name;
    my $ace = join ''
        , qq{\nSequence "$name"\n}, @feature_ace , @ctg_ace
        , qq{\nSequence : "$name"\nDNA "$name"\n\nDNA : "$name"\n$dna\n}
    ;

    return $ace;
}

sub http_response_content {
    my ($self, $command, $script, $args) = @_;

    my $query = $self->toHash;
    $query = { %{$query}, %{$args} } if $args;

    my $response = $self->Client->http_response_content(
        $command, $script, $query);

    return $response;
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

