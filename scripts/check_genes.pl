#!/usr/local/bin/perl

# script to take a list of HUGO names current gene labels and write
# sql required to change them.  ONLY SUITABLE FOR VEGA DATABASEs which
# only one assembly for each clone and the most recent version of each
# gene.

use strict;
use Getopt::Long;
use DBI;
use Sys::Hostname;
use cluster;

# hard wired
my $driver="mysql";
my $port=3306;
my $pass;
my $host='humsrv1';
my $user='ensro';
my $db='otter_human';
my $help;
my $phelp;
my $opt_v;
my $opt_i='';
my $opt_o='large_transcripts.lis';
my $opt_p='duplicate_exons.lis';
my $opt_q='near_duplicate_exons.lis';
my $cache_file='check_genes.cache';
my $make_cache;
my $opt_c='';
my $opt_s=1000000;
my $opt_t;
my $exclude='GD:';
my $ext;
my $vega;
my $stats;

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s', \$port,
	   'pass:s', \$pass,
	   'host:s', \$host,
	   'user:s', \$user,
	   'db:s', \$db,

	   'help', \$phelp,
	   'h',    \$help,
	   'v',    \$opt_v,
	   'i:s',  \$opt_i,
	   'o:s',  \$opt_o,
	   'p:s',  \$opt_p,
	   'q:s',  \$opt_q,
	   'c:s',  \$opt_c,
	   'make_cache',\$make_cache,
	   't:s',  \$opt_t,
	   'exclude:s', \$exclude,
	   'external',  \$ext,
	   'vega',      \$vega,
	   'stats',     \$stats,
	   );

# help
if($phelp){
  exec('perldoc', $0);
  exit 0;
}
if($help){
  print<<ENDOFTEXT;
rename_genes.pl
  -host           char      host of mysql instance ($host)
  -db             char      database ($db)
  -port           num       port ($port)
  -user           char      user ($user)
  -pass           char      passwd

  -h                        this help
  -help                     perldoc help
  -v                        verbose
  -o              file      output file ($opt_o)
  -p              file      output file ($opt_p)
  -q              file      output file ($opt_q)
  -c              char      chromosome ($opt_c)
  -make_cache               make cache file
  -exclude                  gene types prefixes to exclude ($exclude)
  -external                 external genes from vega_set only
  -vega                     vega database (has only assembly)

  -stats                    calculate stats from cache file only
ENDOFTEXT
    exit 0;
}

# connect
my $dbh;
if(my $err=&_db_connect(\$dbh,$host,$db,$user,$pass)){
  print "failed to connect $err\n";
  exit 0;
}

my $n=0;
if($make_cache){

  # get assemblies of interest
  my %a;
  my %ao;
  my $sth;
  if($vega){
    $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version from contig ct, clone cl, chromosome c, assembly a where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id");
  }else{
    $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version, vs.vega_type from contig ct, clone cl, chromosome c, assembly a, sequence_set ss left join vega_set vs on (vs.vega_set_id=ss.vega_set_id) where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id and a.type=ss.assembly_type");
  }
  $sth->execute();
  my $n=0;
  while (my @row = $sth->fetchrow_array()){
    my $cid=shift @row;
    my $other;
    if(!$vega){
      my $vega_type=pop @row;
      if($ext){
	if($vega_type ne 'E'){
	  $other=1;
	}
      }elsif($vega_type eq 'N'){
	$other=1;
      }
    }
    if($other){
      $ao{$cid}=[@row];
    }else{
      $a{$cid}=[@row];
    }
    $n++;
  }
  print "$n contigs read from assembly\n";

  # get exons of current genes
  my $sth=$dbh->prepare("select gsi1.stable_id,gn.name,g.type,tsi.stable_id,ti.name,et.rank,e.exon_id,e.contig_id,e.contig_start,e.contig_end,e.sticky_rank,e.contig_strand,e.phase,e.end_phase from exon e, exon_transcript et, transcript t, current_gene_info cgi, gene_stable_id gsi1, gene_name gn, gene g, transcript_stable_id tsi, current_transcript_info cti, transcript_info ti left join gene_stable_id gsi2 on (gsi1.stable_id=gsi2.stable_id and gsi1.version<gsi2.version) where gsi2.stable_id IS NULL and cgi.gene_stable_id=gsi1.stable_id and cgi.gene_info_id=gn.gene_info_id and gsi1.gene_id=g.gene_id and g.gene_id=t.gene_id and t.transcript_id=tsi.transcript_id and tsi.stable_id=cti.transcript_stable_id and cti.transcript_info_id=ti.transcript_info_id and t.transcript_id=et.transcript_id and et.exon_id=e.exon_id and e.contig_id");
  $sth->execute;
  my $nexclude=0;
  my %excluded_gsi;
  my %offagp_gsi;
  my %onagp_gsi;
  my %reported_gsi;
  my %gsi_ao_clone;
  my %gsi_clone;
  my %atype_gsi;
  my %gsi2gn;
  open(OUT,">$cache_file") || die "cannot open cache file $cache_file";
  while (my @row = $sth->fetchrow_array()){
    $n++;

    # transform to chr coords
    my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecid,$est,$eed,$esr,$es,$ep,$eep)=@row;
    $gsi2gn{$gsi}=$gn;
    if($a{$ecid}){

      my($cname,$atype,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$a{$ecid}};

      # check if exon coordinates are outside AGP
      if($est<$ast || $eed>$aed){
	push(@{$offagp_gsi{$gsi}},join(',',@row));
      }else{
	push(@{$onagp_gsi{$gsi}},join(',',@row));
      }

      my $ecst;
      my $eced;
      if($ao==1){
	$ecst=$acst+$est-$ast;
	$eced=$acst+$eed-$ast;
      }else{
	$ecst=$aced-$est+$ast;
	$eced=$aced-$eed+$ast;
      }
      # constant direction - easier later
      if($ecst>$eced){
	my $t=$ecst;
	$ecst=$eced;
	$eced=$t;
      }
      my @row2=($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep);
      print OUT join("\t",@row2)."\n";
      
      # record clones that each gsi are attached to and assembly for each gsi
      $gsi_clone{$gsi}->{"$cla.$clv"}=1;
      $atype_gsi{$atype}->{$gsi}=1;

    }else{
      $nexclude++;
      push(@{$excluded_gsi{$gsi}},join(',',@row));
      if(ao{$ecid}){
	my($cname,$atype,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$ao{$ecid}};
	$gsi_ao_clone{$gsi}->{"$cla.$clv"}=1;
      }else{
	print "FATAL: $gsi attached to contig $ecid not in assembly table\n";
      }
    }
    last if ($opt_t && $n>=$opt_t);
  }
  close(OUT);
  $dbh->disconnect();

  # report all offtrack genes
  my %orphan_gsi;
  foreach my $atype (sort keys %atype_gsi){
    print "sequence_set $atype\n";
    # report 
    my %sv;
    foreach my $gsi (sort keys %{$atype_gsi{$atype}}){
      if($excluded_gsi{$gsi}){
	$orphan_gsi{$gsi}=1;
	foreach my $sv (keys %{$gsi_clone{$gsi}}){$sv{$sv}=1;}
	my $gn=$gsi2gn{$gsi};
	print " ERR $gsi ($gn) ss=\'$atype\' has exon(s) off assembly:\n";
	print "  ".join("\n  ",@{$excluded_gsi{$gsi}})."\n" if $opt_v;
      }
    }
    my $n=0;
    foreach my $cid (sort {$a{$a}->[2]<=>$a{$b}->[2]} keys %a){
      my($cname,$atype2,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$a{$cid}};
      next if $atype ne $atype2;
      $n++;
      my $sv="$cla.$clv";
      if($sv{$sv}){
	print " [$n] $sv\n";
      }
    }
    my %sv2;
    foreach my $gsi (sort keys %{$atype_gsi{$atype}}){
      if($offagp_gsi{$gsi}){
	foreach my $sv (keys %{$gsi_clone{$gsi}}){$sv2{$sv}=1;}
	my $gn=$gsi2gn{$gsi};
	if($onagp_gsi{$gsi}){
	  print " ERR $gsi ($gn) ss=\'$atype\' some exon(s) off agp:\n";
	}else{
	  print " ERR $gsi ($gn) ss=\'$atype\' all exon(s) off agp:\n";
	}
	print "  ".join("\n  ",@{$offagp_gsi{$gsi}})."\n" if $opt_v;
      }
    }
    my $n=0;
    foreach my $cid (sort {$a{$a}->[2]<=>$a{$b}->[2]} keys %a){
      my($cname,$atype2,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$a{$cid}};
      next if $atype ne $atype2;
      $n++;
      my $sv="$cla.$clv";
      if($sv2{$sv}){
	print " [$n] $sv\n";
      }
    }
  }

  # big problem with orphans - how to tell which elements of assembly
  # are historical?

  if(0){
    foreach my $gsi (keys %excluded_gsi){
      next if $orphan_gsi{$gsi};
      my $atype='ORPHAN';
      my $gn=$gsi2gn{$gsi};
      print "WARN $gsi ($gn) ss=\'$atype\' has exon(s) off assembly:\n  ".
	  join("\n  ",@{$excluded_gsi{$gsi}})."\n";
    }
  }

  print "wrote $n records to cache file $cache_file\n";
  print "wrote $nexclude exons ignored as not in selected assembly\n";
  exit 0;
}

my %gsi;
my %gsi_sum;
my %tsi_sum;
my %atype;
my $n=0;
my $nobs=0;
my $nexclude=0;
my %ngtgnerr;
my %ngtgnerr2;
my %ngtgnerr3;
open(IN,"$cache_file") || die "cannot open $opt_i";
while(<IN>){
  chomp;
  my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep)=split(/\t/);

  # skip obs genes
  if($gt eq 'obsolete'){
    $nobs++;
    next;
  }

  # warn for mislabelled genes
  foreach my $excl (split(/,/,$exclude)){
    if($gt=~/^$excl/ && $gn!~/^$excl/){
      if(!$ngtgnerr2{$gsi}){
	$ngtgnerr2{$gsi}=1;
	print "WARN2 $gsi: type=\'$gt\' but name=\'$gn\'\n" if $opt_v;
      }
    }
  }

  # warn for mislabelled genes/transcripts
  my $gpre='';
  if($gsi=~/^(\w+):/){
    my $gpre=$1;
  }
  my $tpre='';
  if($tsi=~/^(\w+):/){
    my $tpre=$1;
  }
  if($gpre ne $tpre){
    if(!$ngtgnerr3{$tsi}){
      $ngtgnerr3{$tsi}=1;
      print "WARN3 $gsi: $tsi\n";
    }
  }

  my $eflag=0;
  foreach my $excl (split(/,/,$exclude)){
    if($gt=~/^$excl/){
      $nexclude++;
      $eflag=1;
      last;
    }
  }
  next if $eflag;

  # warn for mislabelled genes
  foreach my $excl (split(/,/,$exclude)){
    if($gn=~/^$excl/){
      $eflag=1;
      if(!$ngtgnerr{$gsi}){
	$ngtgnerr{$gsi}=1;
	print "WARN $gsi: type=\'$gt\' but name=\'$gn\'\n" if $opt_v;
      }
    }
  }
  next if $eflag;

  # expect transcripts to stay on same assembly
  if($tsi_sum{$tsi}){
    my($tn2,$cname2,$atype2)=@{$tsi_sum{$tsi}};
    if($cname2 ne $cname){
      print "ERR: $gsi ($gn): $tsi ($tn) on chr $cname and $cname2\n";
    }elsif($atype ne $atype2){
      print "ERR: $gsi ($gn): $tsi ($tn) on chr $atype and $atype2\n";
    }
  }else{
    $tsi_sum{$tsi}=[$tn,$cname,$atype];
  }

  push(@{$gsi{$atype}->{$gsi}},[$tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep]);

  # these relationships should be fixed
  $atype{$atype}=$cname;
  $gsi_sum{$gsi}=[$gn,$gt];

  $n++;
}
close(IN);
print scalar(keys %gsi_sum)." genes read; $nobs obsolete skipped; $nexclude excluded\n";
print "$n name relationships read\n\n";
print scalar(keys %ngtgnerr)." naming errors (GD:name; type)\n";
print scalar(keys %ngtgnerr2)." naming errors (name; GD:type\n";

# another option for script, to use cache file to generate gene count stats
if($stats){
  my %stats;
  foreach my $atype (keys %gsi){
    my $cname=$atype{$atype};
    foreach my $gsi (keys %{$gsi{$atype}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      foreach my $set ($atype,'All'){
	foreach my $type ($gt,'All'){
	  # count genes
	  $stats{$set}->{$type}->[0]++;
	  my %t;
	  my %e;
	  foreach my $re (@{$gsi{$atype}->{$gsi}}){
	    my($tsi,$erank,$eid)=@$re;
	    $t{$tsi}++;
	    $e{$eid}++;
	    # number of exons
	    $stats{$set}->{$type}->[2]++;
	  }
	  # number of transcripts
	  $stats{$set}->{$type}->[1]+=scalar(keys %t);
	  # number of unique exons
	  $stats{$set}->{$type}->[3]+=scalar(keys %e);
	}
      }
    }
  }
  $atype{'All'}='All';
  foreach my $atype (sort keys %stats){
    my $cname=$atype{$atype};
    foreach my $type (sort keys %{$stats{$atype}}){
      printf "%-20s %-25s %6d %6d %6d %6d\n",
      "$atype ($cname)",$type,@{$stats{$atype}->{$type}};
    }
  }
  exit 0;
}

# get clones from assemblies of interest
my %a;
my $sth;
if($vega){
  $sth=$dbh->prepare("select a.type, cl.embl_acc, a.chr_start, a.chr_end, cl.name from clone cl, contig ct, assembly a where a.contig_id=ct.contig_id and ct.clone_id=cl.clone_id");
}else{
  $sth=$dbh->prepare("select a.type, cl.embl_acc, a.chr_start, a.chr_end, cl.name from clone cl, contig ct, assembly a, sequence_set ss, vega_set vs where a.contig_id=ct.contig_id and ct.clone_id=cl.clone_id and a.type=ss.assembly_type and ss.vega_set_id=vs.vega_set_id and vs.vega_type != 'N'");
}
$sth->execute;
my $n=0;
while (my @row = $sth->fetchrow_array()){
  my $type=shift @row;
  my $embl_acc=shift @row;
  $a{$type}->{$embl_acc}=[@row];
  $n++;
  }
print "$n contigs read from assembly\n";

my $nsticky=0;
my $nexon=0;
my %dup_exon;
my $nmc=0;
my $nl=0;
my $flag_v;
open(OUT,">$opt_o") || die "cannot open $opt_o";
open(OUT2,">$opt_p") || die "cannot open $opt_p";
open(OUT3,">$opt_q") || die "cannot open $opt_q";
foreach my $atype (keys %gsi){
  my $cname=$atype{$atype};
  print "Checking \'$atype\' (chr \'$cname\')\n";
  foreach my $gsi (keys %{$gsi{$atype}}){

    # debug:
    if($gsi eq 'OTTHUMG00000032751' && $opt_v){
      $flag_v=1;
      print "debug mode\n";
    }else{
      $flag_v=0;
    }
    
    my($gn,$gt)=@{$gsi_sum{$gsi}};
    my %t2e;
    my %e2t;
    my %e;
    my %eids;
    my %eidso;
    my %elink;
    # look for overlapping exons and group exons into transcripts
    foreach my $rt (@{$gsi{$atype}->{$gsi}}){
      my($tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep)=@{$rt};
      if($e{$eid}){
	# either stored as sticky rank2 or this is sticky rank2
	if($eids{$eid} || $esr>1){

	  my($st,$ed,$es,$ep,$eep)=@{$e{$eid}};

	  # save originals
	  my $esro=1;
	  if($eids{$eid}){
	    $esro=$eids{$eid};
	  }

	  # skip if identical match to old original
	  my $match;
	  foreach my $esr2 (keys %{$eidso{$eid}}){
	    my($st2,$ed2)=@{$eidso{$eid}->{$esr2}};
	    if($st2==$ecst && $ed2==$eced){
	      $match=1;
	    }
	  }

	  # save original before modify so don't check twice
	  $eidso{$eid}->{$esro}=[$st,$ed] unless $eidso{$eid}->{$esro};
	  $eidso{$eid}->{$esr}=[$ecst,$eced] unless $eidso{$eid}->{$esr};
	  $eids{$eid}=1;

	  if($match){
	    # if identical, check for sticky
	  }elsif($ed+1==$ecst){
	    $eids{"$eid.$esr"}=[$ecst,$eced];
	    $ed=$eced;
	    $e{$eid}=[$st,$ed,$es,$ep,$eep];
	    $nsticky++;
	  }elsif($eced+1==$st){
	    $st=$ecst;
	    $e{$eid}=[$st,$ed,$es,$ep,$eep];
	    $nsticky++;
	  }else{
	    print "ERR: duplicate exon id $eid, but no sticky alignment\n";
	  }
	}
      }else{
	my $flag;
	foreach my $eid2 (keys %e){
	  my($st,$ed,$es2,$ep2,$eep2)=@{$e{$eid2}};
	  if($st==$ecst && $ed==$eced){
	    # duplicate exons
	    if($es!=$es2){
	      print OUT3 "NON-DUP: $eid, $eid2 identical but on opposite strands!\n";
	    }elsif($ep!=$ep2){
	      print OUT3 "NON-DUP: $eid, $eid2 identical but on diff phases ($ep,$ep2)\n";
	    }elsif($eep!=$eep2){
	      print OUT3 "WARN NON-DUP: $eid, $eid2 identical but diff end phases ($eep,$eep2) [$ep,$ep2]\n";
	    }elsif($dup_exon{$eid}==$eid2 || $dup_exon{$eid2}==$eid){
	      # don't report again
	    }else{
	      $dup_exon{$eid}=$eid2;
	      print OUT2 "$eid\t$eid2\t$st\t$ed\n";
	    }
	    $flag=1;
	    $eid=$eid2;
	  }else{
	    my $mxst=$st;
	    $mxst=$ecst if $ecst>$mxst;
	    my $mied=$ed;
	    $mied=$eced if $eced<$mied;
	    if($mxst<=$mied){
	      if(1){
		push(@{$elink{$eid}},$eid2);
	      }else{
	      # overlapping exons
		my $mist=$st;
		$mist=$ecst if $ecst<$mist;
		my $mxed=$ed;
		$mxed=$eced if $eced>$mxed;
		$e{$eid2}=[$mist,$mxed];
		$eid=$eid2;
		$flag=1;
	      }
	    }
	  }
	}
	if(!$flag){
	  $e{$eid}=[$ecst,$eced,$es,$ep,$eep];
	  $eids{$eid}=$esr if $esr>1;
	  $nexon++;
	}
      }
      push(@{$t2e{$tsi}},$eid);
      push(@{$e2t{$eid}},$tsi);
    }
    # get size of transcripts and warn of large ones
    my %tse;
    foreach my $tsi (keys %t2e){
      my $mist=1000000000000;
      my $mxed=-1000000000000;
      foreach my $eid (@{$t2e{$tsi}}){
	my($st,$ed)=@{$e{$eid}};
	$mist=$st if $st<$mist;
	$mxed=$ed if $ed>$mxed;
      }
      $tse{$tsi}=[$mist,$mxed];
      my $tsize=$mxed-$mist;
      if($tsize>$opt_s){
	my($tn)=@{$tsi_sum{$tsi}};
	print OUT "WARN $tsize is size of $tsi ($tn), $gsi ($gn,$gt)\n";
	$nl++;
      }
    }
    my $cl=new cluster();
    # link exons by transcripts
    foreach my $tsi (keys %t2e){
      #if(scalar(@{$t2e{$tsi}})>1){
	$cl->link([@{$t2e{$tsi}}]);
	print "D: $tsi ".join(',',@{$t2e{$tsi}})."\n" if $flag_v;
      #}
    }
    # link exons by overlap
    foreach my $eid (keys %elink){
      $cl->link([$eid,@{$elink{$eid}}]);
      print "D: $eid ".join(',',@{$elink{$eid}})."\n" if $flag_v;
    }
    if($cl->cluster_count>1){
      print "$gsi ($gt,$gn) has multiple clusters\n";

      # analysis by overlap of exons
      my $ncid=0;
      foreach my $cid ($cl->cluster_ids){
	$ncid++;
	my %tcl;
	foreach my $eid ($cl->cluster_members($cid)){
	  foreach my $tsi (@{$e2t{$eid}}){
	    $tcl{$tsi}++;
	  }
	}
	print " Cluster $ncid: ".join(',',(keys %tcl))."\n";
      }

      # analysis by overlap of transcripts
      my $last_ed;
      foreach my $tsi (sort {$tse{$a}->[0]<=>$tse{$b}->[0]} keys %tse){
	my($st,$ed)=@{$tse{$tsi}};
	my($tn)=@{$tsi_sum{$tsi}};
	if($last_ed && $last_ed<$st){
	  my $gap=$st-$last_ed;
	  print "  **GAP of $gap bases\n";
	  my $nc=0;
	  my $out='';
	  foreach my $embl_acc (keys %{$a{$atype}}){
	    my($st2,$ed2,$name)=@{$a{$atype}->{$embl_acc}};
	    if($st2>=$last_ed && $st2<=$st){
	      $nc++;
	      $out.="    Boundary of $embl_acc ($name)\n";
	    }
	    if($ed2>=$last_ed && $ed2<=$st){
	      $nc++;
	      $out.="    Boundary of $embl_acc ($name)\n";
	    }
	  }
	  if($nc<=2){
	    print $out;
	  }
	}
	print "  $tsi ($tn): $st-$ed\n";
	$last_ed=$ed;
      }
      $nmc++;
    }
  }
}
print scalar(keys %dup_exon)." duplicate exons\n";
print "$nmc genes with non overlapping transcripts\n";
print "found $nexon exons; $nsticky sticky exons\n";
print "$nl large transcripts\n";
close(OUT);
close(OUT2);
close(OUT3);

exit 0;

# connect to db with error handling
sub _db_connect{
  my($rdbh,$host,$database,$user,$pass)=@_;
  my $dsn = "DBI:$driver:database=$database;host=$host;port=$port";
  
  # try to connect to database
  eval{
    $$rdbh = DBI->connect($dsn, $user, $pass,
			  { RaiseError => 1, PrintError => 0 });
  };
  if($@){
    print "$database not on $host\n$@\n" if $opt_v;
    return -2;
  }
}

__END__


=pod

=head1 rename_genes.pl

=head1 DESCRIPTION

=head1 EXAMPLES

=head1 FLAGS

=over 4

=item -h

Displays short help

=item -help

Displays this help message

=back

=head1 VERSION HISTORY

=over 4

=item 17-MAR-2004

B<th> released first version

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
