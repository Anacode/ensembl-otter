package Evi::Taxonamer;

# Find out and cache the taxon_id<->taxon_name mapping globally

use IO::Socket;
my $host=$ENV{'GETZHOST'} || "cbi2";
my $port=$ENV{'GETZPORT'} || "20204";

my %waiting	= ();
my %data	= ();

sub put_id {    # use this method to register the id's
                # can be called as Taxonamer-> or Taxonamer::

    if (my $taxon_id = pop @_) {
	    if(not $data{$taxon_id}) {
		    $waiting{$taxon_id}=1;
	    }
    } else {
        warn "Missing taxon ID argument";
    }
}

sub fetch {
	if(! %waiting) {
		print STDERR "Taxonamer: nothing to be fetched\n";
		return;
	}

	my @lines = getz('-f', 'id spc', '[taxonomy-id:'.join('|', keys %waiting).']');
	while(@lines) {
		my $taxon_id = (split(/(\s*:\s*|\s*\n)/,shift @lines))[2];
		my $name	 = (split(/(\s*:\s*|\s*\n)/,shift @lines))[2];

		$data{$taxon_id} = $name;
		delete $waiting{$taxon_id};
		print STDERR "Taxonamer: found [$taxon_id] --> [$name]\n";
	}

	for my $taxon_id (keys %waiting) { # get rid of the rest just once
		$data{$taxon_id} = "TAXON-${taxon_id}";
		delete $waiting{$taxon_id};
		warn "Taxonamer: could not find taxon with ID = $taxon_id\n";
	}
}

sub get_name {					# a normal usage is Taxonamer::get_name(9606)
	my $taxon_id 	= pop @_;	# in case someone wants to use Taxonamer->get_name() notation

	put_id($taxon_id);

	if( %waiting) {
		fetch();
	}
	return $data{$taxon_id};
}

# code borrowed from SRS.pm

sub getz {

    my $sockh = IO::Socket::INET->new( PeerAddr => $host,
                                       PeerPort => $port, 
                                       Type     => SOCK_STREAM,
                                       Proto    => 'tcp',
                                       ) or die "Socket could not be opened, because: $!\n";
    
    $sockh->autoflush(1);
    
    print $sockh join('___', @_) . "\n"; 
    
    my $dest_array = wantarray;

    if (defined($dest_array)) {
        if ($dest_array) {
            return <$sockh>;
        } else {
            local $/ = undef;
            return <$sockh>;
        }
    } else {
        while (<$sockh>) {
            print $_;
        }
        $sockh->close;
    }
}

1;
