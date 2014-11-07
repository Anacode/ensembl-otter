package Bio::Otter::Utils::AutoOpen;
use strict;
use warnings;
use Try::Tiny;
use Time::HiRes qw( gettimeofday tv_interval );


=head1 NAME

Bio::Otter::Utils::AutoOpen - helper to get a window opened "automatically"

=head1 DESCRIPTION

Consstructing the object starts the process, and it hooks itself onto
an after callback.  The object will forget itself when the work is
complete.  If it fails, the error will go to the MainLoop handler.

There isn't much public API, because the internals should be expected
to change with the GUI.

=head2 Open syntax

By example,

 --open human_dev                                 Dataset
 --open human_dev/chr12-38                        SequenceSet
 --open human_dev/chr12-38/1_000_000:2_000_000    Region, by coords
 --open human_dev/chr12-38/1_000_000+1_000_000    Region, by start + length
 --open 'human_dev/chr12-38/#5'                   Region, by clone index
 --open 'human_dev/chr12-38/#5..8'                Region, by clone indices
 --open human_dev/chr12-38/AC004803               Region, by name
 --open human_dev/chr12-38/AC004803-KC877505.1    Region, by start-end names

 --open human_dev/chr12-38/view:...               Region, read-only
 --open human_dev/chr12-38/v:...                  Region, read-only

For matches by clone name, C<.SV> is optional and ignored.

For coordinates, underscores to mark digit groups are optional and
ignored.

Currently for chromosome coordinates, the range will be rounded to
clone boundaries.


=head1 CAVEATS

This bypasses some parts of the UI to get the job done, hence those
parts are not tested by this route.

If multiple regions are opened, currently they will run in parallel.
Might be better to chain them on L</_done>.

=cut

sub new {
    my ($pkg, $SpeciesListWindow, $openspec) = @_;
    my $self = { _SLW => $SpeciesListWindow, name => $openspec };
    bless $self, $pkg;
    $self->_init;
    return $self;
}

sub name {
    my ($self) = @_;
    return $self->{name};
}

sub hide_after {
    my ($self, @set) = @_;
    ($self->{hide_after}) = @set if @set;
    return $self->{hide_after};
}

sub _SLW {
    my ($self) = @_;
    return $self->{_SLW};
}

sub _more_work {
    my ($self) = @_;
    return @{ $self->{_work} } ? 1 : 0;
}

sub _take_work {
    my ($self) = @_;
    return shift @{ $self->{_work} };
}

sub _init {
    my ($self) = @_;
    my @work;
    $self->{_work} = \@work;
    my $t0 = $self->{t0} = [ gettimeofday() ];

    my ($ds, $seq_region, $pos) = split '/', $self->name, 3;
    # later, should take a 4th part to specify ColumnChooser options

    die "Open shortcut syntax: --open dataset[:seq_region]\n" unless $ds;
    push @work, [ open_dataset_by_name => $ds ];
    push @work, [ open_sequenceseq_by_name => $seq_region ] if defined $seq_region;

    push @work, [ 'open_region_readonly' ]
      if defined $pos && $pos =~ s{^v(iew)?:}{};

    if (defined $pos && $pos =~ m{^(\d[0-9_]*)(:|\+)(\d[0-9_]*)$}) {
        my @n = ($1, $3);
        my $op = $2;
        foreach (@n) { s/_//g }
        $n[1] += $n[0] if $op eq '+';
        push @work, [ open_region_by_coords => @n ];
    } elsif (defined $pos && $pos =~ m{^#(\d+)$}) {
        push @work, [ open_region_by_index => $1, $1 ];
    } elsif (defined $pos && $pos =~ m{^#(\d+)\.\.(\d+)$}) {
        push @work, [ open_region_by_index => $1, $2 ];
    } elsif (defined $pos) {
        push @work, [ open_region_by_names => split '-', $pos, 2 ];
    }

    $self->logger->info(sprintf("Queued %s at \$^T+%.2fs",
                                $self->name, tv_interval([$^T,0], $t0)));
    return $self->_hook;
}

sub logger {
    return Log::Log4perl->get_logger('AutoOpen');
}

sub _hook {
    my ($self) = @_;
    if ($self->_more_work) {
        my $mw = $self->_SLW->top_window;
        $mw->afterIdle([ $self, 'do_open' ]);
    } else {
        $self->_done;
    }
    return;
}

sub _done {
    my ($self) = @_;

    # we leave the mainwindow visible until we're done opening
    my $mw = $self->_SLW->top_window;
    $mw->iconify if $self->hide_after;

    $self->logger->info(sprintf("Finished %s in %.2fs",
                                $self->name, tv_interval($self->{t0})));
    return;
}

sub do_open {
    my ($self) = @_;

    my $next = $self->_take_work;
    my ($method, @arg) = @$next;
    die "Don't know how to ($method, @arg) yet" unless $self->can($method);
    $self->logger->debug("$method(@arg)");
    $self->$method(@arg);

    return $self->_hook;
}

sub open_dataset_by_name {
    my ($self, $ds) = @_;
    my $ssc = $self->_SLW->open_dataset_by_name($ds);
    $self->{ssc} = $ssc; # a CanvasWindow::SequenceSetChooser
    $ssc->top_window->iconify if $self->_more_work;
    return;
}

sub open_sequenceseq_by_name {
    my ($self, $seq_region) = @_;
    my $ssc = $self->{ssc}
      or die "Cannot open_sequenceseq_by_name without a CanvasWindow::SequenceSetChooser";

    my $sn = $ssc->open_sequence_set_by_ssname_subset($seq_region, undef);
    $self->{sn} = $sn; # a CanvasWindow::SequenceNotes
    $sn->set_write_ifposs;
    $sn->top_window->iconify if $self->_more_work;
    return;
}

sub open_region_readonly {
    my ($self, $start, $end) = @_;
    my $sn = $self->{sn}
      or die "Cannot open_region_readonly without CanvasWindow::SequenceNotes";
    $sn->set_read_only;
    return;
}

sub open_region_by_coords {
    my ($self, $start, $end) = @_;
    my $sn = $self->{sn}
      or die "Cannot open_region_by_coords without CanvasWindow::SequenceNotes";
    $sn->run_lace_on_slice($start, $end);
    return;
}

sub open_region_by_index {
    my ($self, $first, $last) = @_;
    my $sn = $self->{sn}
      or die "Cannot open_region_by_index without CanvasWindow::SequenceNotes";
    my $cs_list = $sn->get_CloneSequence_list; # ensures it is fetched
    my $ss = $sn->SequenceSet;
    my $max = @$cs_list; # indices are 1-based
    my $name = $sn->name; # or $ss->name?
    die "Invalid clone index range #$first..$last (incl.) on $name, valid is 1..$max\n"
      if $first < 1 || $first > $last || $first > $max || $last > $max;

    my @selected = @{$cs_list}[$first-1 .. $last-1];
    $ss->selected_CloneSequences(\@selected);
    return $self->_open_region_selected($sn);
}

sub open_region_by_names {
    my ($self, $start, $end) = @_;
    my $sn = $self->{sn}
      or die "Cannot open_region_by_hunt without CanvasWindow::SequenceNotes";
    my $ss = $sn->SequenceSet;

    foreach ($start, $end) { s{\.\d+$}{} }
    # this API matches ACC without .SV

    $ss->select_CloneSequences_by_start_end_accessions($start, $end);
    # can fail to find

    return $self->_open_region_selected($sn);
}

sub _open_region_selected {
    my ($self, $sn) = @_;
    $sn->open_SequenceSet($self->name);
    return;
}


1;