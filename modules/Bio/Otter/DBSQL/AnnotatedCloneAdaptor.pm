package Bio::Otter::DBSQL::AnnotatedCloneAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::Otter::AnnotatedClone;

use Bio::EnsEMBL::DBSQL::CloneAdaptor;
use Bio::Otter::DBSQL::AnnotatedCloneAdaptor;
use Bio::Otter::CloneInfo;
use Bio::Otter::DBSQL::CurrentCloneInfoAdaptor;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::CloneAdaptor);


# This is assuming the otter info and the ensembl genes are in the same database 
# and so have the same adaptor

### JGRG - no reason for this to be different to new() in BaseAdaptor?
###        Commented out.
#sub new {
#    my ($class,$dbobj) = @_;
#
    #my $self = {};
    #bless $self,$class;

    #if( !defined $dbobj || !ref $dbobj ) {
    #    $self->throw("Don't have a db [$dbobj] for new adaptor");
    #}

    #$self->db($dbobj);

#    return $self;
#}

=head2 fetch_by_accession_verion

 Title   : fetch_by_accession_version
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_accession_version {
   my ($self,$accession,$version) = @_;

   if (!defined($accession)) {
       $self->throw("Must enter an accession to fetch an AnnotatedClone");
   }
   if (!defined($version)) {
       $self->throw("Must enter a version to fetch an AnnotatedClone");
   }

   my  $clone = $self->SUPER::fetch_by_accession_version($accession,$version);

   $self->annotate_clone($clone);
   
   return $clone;
   
}


=head2 fetch_by_dbID

 Title   : fetch_by_dbID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_dbID {
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("Must enter a clone dbID to fetch an AnnotatedGene");
   }

   my  $clone = $self->SUPER::fetch_by_dbID($id);

   $self->annotate_clone($clone);

   return $clone;
   
}

=head2 annotate_clone

 Title   : annotate_clone
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub annotate_clone {
   my ($self,$clone) = @_;

   # Make the clone an AnnotatedClone unless it is already
   unless ($clone->isa('Bio::Otter::AnnotatedClone')) {
       bless $clone, 'Bio::Otter::AnnotatedClone';
   }

   my $clone_info_adaptor         = $self->db->get_CloneInfoAdaptor();
   my $current_clone_info_adaptor = $self->db->get_CurrentCloneInfoAdaptor();

   my $infoid = $current_clone_info_adaptor->fetch_by_accession_version($clone->id,$clone->embl_version);
   my $info;

   if ($infoid) {
     $info = $clone_info_adaptor->fetch_by_dbID($infoid);
   } else {
     $info = new Bio::Otter::CloneInfo;
   }
   $clone->clone_info($info);

}

=head2 fetch_by_Slice

  Arg [1]    : Bio::EnsEMBL::Slice $slice
               the slice to fetch genes from
  Example    : $clones = $clone_adaptor->fetch_by_slice($slice);
  Description: Retrieves all genes which are present on a slice
  Returntype : list of Bio::EnsEMBL::Genes in slice coordinates
  Exceptions : nonetail -
  Caller     : Bio::EnsEMBL::Slice

=cut

sub fetch_by_Slice {
  my ( $self, $slice) = @_;

  my @out;
  my $mapper = $self->db->get_AssemblyMapperAdaptor->fetch_by_type
    ( $slice->assembly_type() );

  $mapper->register_region( $slice->chr_name(),
			    $slice->chr_start(),
			    $slice->chr_end());
  
  my @cids = $mapper->list_contig_ids( $slice->chr_name(),
				       $slice->chr_start(),
				       $slice->chr_end());
  # no contigs found so return
  if ( scalar (@cids) == 0 ) {
    return [];
  }

  my @clones;
 
  foreach my $cid (@cids) {
     my $contig = $self->db->get_RawContigAdaptor->fetch_by_dbID($cid);

     my $clone  = $contig->clone;

     $clone->annotate_clone;

     push(@clones,$clone);
  }

  return \@clones;
      
}


=head2 store

 Title   : store
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub store{
    my ($self,$clone) = @_;

    if (!defined($clone)) {
        $self->throw("Must enter an AnnotatedClone object to the store method");
    }
    if (!$clone->isa("Bio::Otter::AnnotatedClone")) {
        $self->throw("Object must be an AnnotatedClone object. Currently [$clone]");
    }

    my $info = $clone->clone_info
        || $self->throw("Annotated clone must have a clone info object");

    # print STDERR "Ann id " . $clone->stable_id . "\n";

    my $clone_info_adaptor = $self->db->get_CloneInfoAdaptor();
    my $current_c_info_ad = $self->db->get_CurrentCloneInfoAdaptor;

    my $clone_id = $clone->dbID
        || $self->throw('clone does not have a dbID');
    $clone->dbID($clone_id);
    $info->clone_id($clone_id);
    $clone_info_adaptor->store($info);
    $current_c_info_ad->store($clone);
}

#sub _fetch_clone_id {
#    my( $self, $clone ) = @_;
#    
#    my $acc = $clone->embl_id      or $self->throw('embl_id missing from Clone');
#    my $sv  = $clone->embl_version or $self->throw('embl_version missing from Clone');
#    
#    my $sth = $self->prepare(q{
#        SELECT clone_id
#        FROM clone
#        WHERE embl_acc = ?
#          AND embl_version = ?
#        });
#    $sth->execute($acc, $sv);
#    my ($clone_id) = $sth->fetchrow;
#    return $clone_id;
#}

1;

	





