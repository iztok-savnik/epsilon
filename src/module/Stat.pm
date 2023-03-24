=pod

=head1 NAME 

I<Stat.pm> (v0.1) -- Computing and using statistics for large RDF
datasets.

=head1 DESCRIPTION

Module I<Stat.pm> computes statistics of RDF triple-store. It
implements methods that facilitate the use of statistics in
I<epsilon>.

Statistics of triple store is represented by means of an associative
array indexed by key patterns of the form (S,P,O) where S,P,O are either
class identifiers, or, empty holes. The algorithm for the computation
of statistics is defined as follows.

=head2 Computation of statistics for one triple

Here we sketch the algorithm for the computation of statistics 
for RDF triple-store. 

1) For each ground triple C<(s,p,o)> entered into I<Stat.pm> first compute
types of each particular component s,p,o yielding sets of class
identifiers tS,tP,tO.  

2) Transitive closure of sets tS,tP,tO is computed
with respect to relationship rdfs:subClass to obtain all classes of
componentes s,p,o. Transitive closures of sets tS,tP,tO are denoted
ctS,ctP,ctO. 

3) Let C<->" denote hole. For each key pattern (ts,tp,to) from (ctS|-)
x (ctP|-) x (ctO|-) add one to C<$stat{(ts,tp,to)}>.

=head2 Internal representation of C<%stat> key pattern

Pattern ([s|-],[p|-],[o|-]), where s,p,o are class identifiers, is
internally represented as key $ix-$id-$id1-$id2. Index $ix is used to
select particular type of key: S,P,O,SP,SO,PO,SPO. Values $id, $id1 
represent values of s,p,o with respect to the key. 

Implemenetation in C<big3store> shall include clear definition of 
key pattern data structure. Note that we do not use key pattern SPO
in this implementation.

=cut

package Stat;

use DB_File;
use BerkeleyDB;

=head2 Data structures

=over 12

=cut
BEGIN {
    # constants
    $Ok = 1;
    $OOk = 2;
    $True = 1;
    $False = 0;

    # primes for hash function
    $prime1 = 16000057;
    $prime2 = 257;
    $prime3 = 4001;

    $ul = "\e[36;38m";
    $ue = "\e[37m";

    #$prime1 = 1000000007;
    #$prime2 = 31627;
    #$prime3 = 484019;

#    $prime1 = 49999;
#    $prime2 = 223;
#    $prime3 = 1361;

    # size of memory for 1 key type
    $szmem = 50000;
    # 2.5G (avail mem) / 50K (size of schemata) = 50K 

=item I<%stat>

Hash C<%stat> is indexed by the key types. It stores the number of 
keys (including duplicates) for a given key type.

=cut
   # $dbdesc = new DB_File::HASHINFO; 
   #tie %stat, 'DB_File', "./stat.db", O_CREAT|O_RDWR, 0777, $DB_HASH;
   tie %stat, 'BerkeleyDB::Btree', 
                -Cachesize => 100000000,
                -Filename  => "data/stat.db", 
                -Flags     => DB_CREATE; #|DB_RDONLY;

=item I<%stat1>

Hash C<%stat1> is indexed by the key types. It stores the number of 
distinct keys for a given key type.

=cut
   # $dbdesc = new DB_File::HASHINFO; 
   #tie %stat1, 'DB_File', "./stat1.db", O_CREAT|O_RDWR, 0777, $DB_HASH;
   tie %stat1, 'BerkeleyDB::Btree', 
                -Cachesize => 100000000,
                -Filename  => "data/stat1.db", 
                -Flags     => DB_CREATE; #|DB_RDONLY;

=item I<%stad>

Hash C<%stad> is indexed by the key types. It includes the memory for the 
computation of the distict keys of a given key type.

=cut
   %stad = ();

=item I<$stad_wind>

The size of the window used to estimate the number of distinct instances for 
a given schema triple.

=cut
#   $stad_wind = 4000;   # stable
   $stad_wind = 1000;

=item I<$stad_prob>

The probability (in %) that an identifier that pops out of the window is 
a new identifier. 

=cut
#   $stad_prob = 85;     # stable
   $stad_prob = 83; 

=item I<%cach>

Hash table C<%cach> is a cache for the transitive closures of the classes.

=cut
   %cach = ();

=item I<$bound>

The mode of statistics is either bound or unbound. 

=cut
   $bound = $False;
}

=back

=head1 Functions

=over 12

=item C<\@bts = mem_create($sz)>

Create a sequence of bits of the size $sz. 
(*Adhoc implementation of bitstrings. To be improved.*)

=cut
sub mem_create {
    my $sz = shift;

    #my $byt = ($sz/8)+1;
    #my @bts = (0x00) x $sz;
    my %bts = ();
    return \%bts;
}

=item C<ok = mem_set(\%bp, $nt)>

Set the value of the $nt-th bit in the memory \%bp to 1.

=cut
sub mem_set {
    my $bp = shift;
    my $nt = shift;

    #my $byt = ($sz/8)+1;
    $bp->{$nt} = 0x01;
}

=item C<$bt = mem_get(\%bp, $nt)>

Return the value of the $nt-th bit from the memory \%bp.

=cut
sub mem_get {
    my $bp = shift;
    my $nt = shift;

    #my $byt = ($sz/8)+1;
    if (defined($bp->{$nt})) { return 1; }
    else                     { return 0; }
}

=item C<$cn = mem_count(\@bp)>

Count the number of 1's in the memory \@bp. 

=cut
sub mem_count {
    my $bp = shift;

    my $cn = 0;;
    foreach my $k (keys %{$bp} ) {
        $cn++;
    }
    return $cn;
}

=item C<ok = hash($ix,$tri)>

Compute a hash value for a given index $ix from a given triple $tri.

=cut
sub hash {
    my $ix = shift;    # column index of tuple (of $stor) 
    my $tri = shift;   # column index of tuple (of $stor) 

    my $h;
    if    ($ix == 3) { $h = ($prime3 * $tri->[0]) % $prime1; }
    elsif ($ix == 4) { $h = ($prime3 * $tri->[1]) % $prime1;  }
    elsif ($ix == 5) { $h = ($prime3 * $tri->[2]) % $prime1; }
    elsif ($ix == 6) { $h = ($prime3 * $tri->[0] + $prime2 * $tri->[1]) % $prime1; }
    elsif ($ix == 7) { $h = ($prime3 * $tri->[0] + $prime2 * $tri->[2]) % $prime1; }
    elsif ($ix == 8) { $h = ($prime3 * $tri->[1] + $prime2 * $tri->[2]) % $prime1; }
    elsif ($ix == 9) { $h = ($prime3 * $tri->[0] + $prime2 * $tri->[1] + $tri->[2]) % $prime1; }
    return $h;
}

=item C<ok = inc($ix, $id [, $id1, [, $id2]])>

Increment counter of a key type $ix-$id[-$id1[-$id2]].

=cut
sub inc {
    # calc key pattern
    my $ix = shift;    
    my $id = shift;    
    my $id1 = shift;
    my $id2 = shift;
    my $ky = &Mstore::make_keytype($bound,$ix,$id,$id1,$id2);

    if (defined($stat{$ky})) {
        $stat{$ky}++;
    } else {
        $stat{$ky} = 1;
    }
}

=item C<ok = inc_dist1($tri, $ix, $id [, $id1, [, $id2]])>

Increment counters of distinct values from $tri of key type 
$ix-$id[-$id1[-$id2]]. (*Obsolete*)

=cut
sub inc_dist1 {
    # calc key pattern
    my $tri = shift,
    my $ix = shift;    
    my $id = shift;    
    my $id1 = shift;
    my $id2 = shift;
    my $kyt = &Mstore::make_keytype($bound,$ix,$id,$id1,$id2);
    #my $keyval = &Mstore::make_keyval($tri,$ix);

    # frst the val of hash function
    my $h = &hash($ix,$tri);
    my $mp; 

    # create mem if does not exist
    if (!defined($stad{$kyt})) {
	$mp = &mem_create($szmem);
        $stad{$kyt} = $mp;
    } else {
        $mp = $stad{$kyt};
    }

    # update memory
    &mem_set($mp,$h) if ($h < $szmem);
}

=item C<ok = inc_dist($tri, $ix, $id [, $id1, [, $id2]])>

Increment counteris of distinct keys from a triple $tri. The triple
$tri has the key type $ix-$id[-$id1[-$id2]].

=cut
sub inc_dist {
    # calc key pattern
    my $tri = shift,
    my $ix = shift;    
    my $id = shift;    
    my $id1 = shift;
    my $id2 = shift;
    my $ky = &Mstore::make_keytype($bound,$ix,$id,$id1,$id2);
    my $keyval = &Mstore::make_keyval($tri,$ix);

    # debug print
    #my @a1 = split "-", $ky;
    #my @a2 = split "-", $keyval;
    #shift @a1; 
    #shift @a2;
    #@a1 = map { &KeyID::to_key($_) } @a1;
    #@a2 = map { &KeyID::to_key($_) } @a2;
    #unshift(@a1, $ix); unshift(@a2, $ix);
    #my $k1 = join '-', @a1;
    #my $k2 = join '-', @a2;
    #print "key=($ky)$k1:val=($keyval)$k2\n";

    # $ky undef in %stad => init entry for $ky
    if (!defined($stad{$ky})) {

        $stad{$ky} = {};
        $stad{$ky}->{$keyval} = 1;
        $stad{$ky}->{"prev-".$keyval} = "null";
        $stad{$ky}->{"next-".$keyval} = "null";
        $stad{$ky}->{"first-key"} = $keyval;
        $stad{$ky}->{"last-key"} = $keyval;
        $stad{$ky}->{"num-elem"} = 1;
        $stad{$ky}->{"dist-val"} = 0;

        #print "-----case=1:key=$ky:val=$keyval".
        #            ":num=".$stad{$ky}->{"num-elem"}.
        #            ":first=".$stad{$ky}->{"first-key"}.
        #            ":last=".$stad{$ky}->{"last-key"}.
        #            ":prev=".$stad{$ky}->{"prev-".$keyval}.
        #            ":next=".$stad{$ky}->{"next-".$keyval}.":";
        #&print_list($ky,$keyval);
        #print "\n";
        #for my $k (keys %{$stad{$ky}}) {
        #    print "$k:".$stad{$ky}->{$k}."\n";
        #}

    # $keyval defined in $stad{$ky} => put it on top
    } elsif (defined($stad{$ky}->{$keyval})) {

        $stad{$ky}->{$keyval}++;
        my $first = $stad{$ky}->{"first-key"};

        # nothing to do if $keyval = $first
        if ($keyval ne $first) {
    
            my $prev = $stad{$ky}->{"prev-".$keyval};
            my $next = $stad{$ky}->{"next-".$keyval};

            # unlink $keyval
            if ($prev ne "null") {
                $stad{$ky}->{"next-".$prev} = $next;
            }
            if ($next ne "null") {
                $stad{$ky}->{"prev-".$next} = $prev;
            } else {
                $stad{$ky}->{"last-key"} = $prev;
            }

            # put it to front
            $stad{$ky}->{"prev-".$first} = $keyval;
            $stad{$ky}->{"prev-".$keyval} = "null";
            $stad{$ky}->{"next-".$keyval} = $first;
            $stad{$ky}->{"first-key"} = $keyval;
        }

        #print "-----case=2:key=$ky:val=$keyval".
        #            ":num=".$stad{$ky}->{"num-elem"}.
        #            ":first=".$stad{$ky}->{"first-key"}.
        #            ":last=".$stad{$ky}->{"last-key"}.
        #            ":prev=".$stad{$ky}->{"prev-".$keyval}.
        #            ":next=".$stad{$ky}->{"next-".$keyval}.":";
        #&print_list($ky,$keyval);
        #print "\n";
        #for my $k (keys %{$stad{$ky}}) {
        #    print "$k:".$stad{$ky}->{$k}."\n";
        #}

    # $keyval not defined in $stad{$ky}
    } else {

        # put it to front
        my $first = $stad{$ky}->{"first-key"};
        $stad{$ky}->{"prev-".$first} = $keyval;
        $stad{$ky}->{"prev-".$keyval} = "null";
        $stad{$ky}->{"next-".$keyval} = $first;

        $stad{$ky}->{$keyval} = 1;
        $stad{$ky}->{"first-key"} = $keyval;

        # window full => drop last out
        if ($stad_wind <= $stad{$ky}->{"num-elem"}) {

            # remove last from list
            my $last = $stad{$ky}->{"last-key"};
            my $newLst = $stad{$ky}->{"prev-".$last};
            $stad{$ky}->{"next-".$newLst} = "null";
            $stad{$ky}->{"last-key"} = $newLst;

            # calc probability that we have new dist-val
            # probability fixed for now!
            if (rand(100) < $stad_prob) {
                $stad{$ky}->{"dist-val"}++;
            }

            # delete last
            delete($stad{$ky}->{$last});
            delete($stad{$ky}->{"next-".$last});
            delete($stad{$ky}->{"prev-".$last});

        # window not full, just inc num-elem
	} else {
            $stad{$ky}->{"num-elem"}++;
        }

        #print "-----case=3:key=$ky:val=$keyval".
        #            ":num=".$stad{$ky}->{"num-elem"}.
        #            ":first=".$stad{$ky}->{"first-key"}.
        #            ":last=".$stad{$ky}->{"last-key"}.
        #            ":prev=".$stad{$ky}->{"prev-".$keyval}.
        #            ":next=".$stad{$ky}->{"next-".$keyval}.":";
        #&print_list($ky,$keyval);
        #print "\n";
        #for my $k (keys %{$stad{$ky}}) {
        #    print "$k:".$stad{$ky}->{$k}."\n";
        #}
    }
}

sub print_list {
    my $ke = shift;
    my $em = shift;

    print "key=$em;num=".$stad{$ke}->{$em}.":";

    my $nx = $stad{$ke}->{"next-".$em}; 
    if ($nx ne "null") {
        &print_list($ke,$nx)
    }
}

=item C<ok = collect_stat_distinct()>

Collect statistics records for each instances of schema triples and 
store counters of distinct instances back in %stad.

=cut
sub collect_stat_distinct {
    my $k;
    for $k (keys %stad) {
        #$stat1{$k} = $stad{$k}->{"dist-val"} + ($stad_prob/100)*$stad{$k}->{"num-elem"};
        $stat1{$k} = $stad{$k}->{"dist-val"} + ($stad_prob/100)*$stad{$k}->{"num-elem"};
        #$stat1{$k} = int(&mem_count($stad{$k})*($prime1/$szmem));
    }
}

=item C<ok = insert_triple_prop($tri)>

Update statistics of the stored schema graph for one triple $tri. 
Compute class identifiers for each component of $tri using properties 
rdfs:domain, rdfs:range and rdfs:subPropertyOf. Generate all stored
schema triples that are the types of $tri. Increment the counters 
for each of the stored schema triples.

=cut
sub insert_triple_prop {
    my $tri = shift;

    # print triple
    print "---------------------------------------------\n";
    print "tri=".&KeyID::to_key($tri->[0]).",".
                 &KeyID::to_key($tri->[1]).",".
                 &KeyID::to_key($tri->[2])."\n";

    # calc class idents of P
    my %a2 = ();
    my $pa2 = \%a2;
    $a2{$tri->[1]} = $Ok;  # add P to a2
    my $sp = &KeyID::to_id("rdfs:subPropertyOf");
    &Kgraph::close_generalize($pa2, $sp);    

    # prepare store for domain and range cls 
    my %a1 = ();
    my %a3 = ();
    my $pa1 = \%a1;
    my $pa3 = \%a3;

    # marking entries 'done'
    my %entr = ();    

    # loop thru predicates
    my ($cS,$cO,$hd_S,$hd_O,$rc_S,$rc_O);
    my $sc_S = &KeyID::to_id("rdfs:domain");
    my $sc_O = &KeyID::to_id("rdfs:range");
    my $p = $tri->[1];

    # get domains of $p
    $hd_S = &Mstore::open_scan(6,$p,$sc_S);
    do {
        # get next $cS
        if (!defined($hd_S)) {
            # no schema => default
            $cS = &KeyID::to_id("owl:Thing");
        } else {
            # take class of domain of $p
            $rc_S = &Mstore::scan_next($hd_S);
            $cS = $rc_S->[2];
        }

        # insert cS in a1
        $pa1->{$cS} = $Ok;

        # get ranges of $p and updte stat
        $hd_O = &Mstore::open_scan(6,$p,$sc_O);
        do {
            # get next $cO
            if (!defined($hd_O)) {
                # no schema => default
                $cO = &KeyID::to_id("owl:Thing");
            } else {
                # take class of range of $p
                $rc_O = &Mstore::scan_next($hd_O);
                $cO = $rc_O->[2];
            }

            # insert cS in a1
            $pa3->{$cO} = $Ok;

        } while (defined($hd_O) && !&Mstore::scan_eor($hd_O)); 
    } while (defined($hd_S) && !&Mstore::scan_eor($hd_S)); 

    # print sets
    &Kgraph::set_print("pa1=",$pa1);
    &Kgraph::set_print("pa2=",$pa2);
    &Kgraph::set_print("pa3=",$pa3);

    # insert stat for SPO classes
    for $cS (keys %{$pa1}) {
    for $p (keys %{$pa2}) {
    for $cO (keys %{$pa3}) {

        if ($bound && !defined($entr{"3-$cS-$p-$cO"})) { 
            $entr{"3-$cS-$p-$cO"} = $Ok;
            &inc(3,$cS,$p,$cO);
            &inc_dist($tri,3,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"3-$cS"})) {
            $entr{"3-$cS"} = $Ok;
            &inc(3,$cS);
            &inc_dist($tri,3,$cS);
        }

        if ($bound && !defined($entr{"4-$cS-$p-$cO"})) { 
            $entr{"4-$cS-$p-$cO"} = $Ok;
            &inc(4,$cS,$p,$cO);
            &inc_dist($tri,4,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"4-$p"})) {
            $entr{"4-$p"} = $Ok;
            &inc(4,$p);
            &inc_dist($tri,4,$p);
        }

        if ($bound && !defined($entr{"5-$cS-$p-$cO"})) { 
            $entr{"5-$cS-$p-$cO"} = $Ok;
            &inc(5,$cS,$p,$cO);
            &inc_dist($tri,5,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"5-$cO"})) {
            $entr{"5-$cO"} = $Ok;
            &inc(5,$cO);
            &inc_dist($tri,5,$cO);
        }

        if ($bound && !defined($entr{"6-$cS-$p-$cO"})) { 
            $entr{"6-$cS-$p-$cO"} = $Ok;
            &inc(6,$cS,$p,$cO);
            &inc_dist($tri,6,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"6-$cS-$p"})) {
            $entr{"6-$cS-$p"} = $Ok;
            &inc(6,$cS,$p);
            &inc_dist($tri,6,$cS,$p);
        }

        if ($bound && !defined($entr{"7-$cS-$p-$cO"})) { 
            $entr{"7-$cS-$p-$cO"} = $Ok;
            &inc(7,$cS,$p,$cO);
            &inc_dist($tri,7,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"7-$cS-$cO"})) {
            $entr{"7-$cS-$cO"} = $Ok;
            &inc(7,$cS,$cO);
            &inc_dist($tri,7,$cS,$cO);
        }
  
        if ($bound && !defined($entr{"8-$cS-$p-$cO"})) { 
            $entr{"8-$cS-$p-$cO"} = $Ok;
            &inc(8,$cS,$p,$cO);
            &inc_dist($tri,8,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"8-$p-$cO"})) {
            $entr{"8-$p-$cO"} = $Ok;
            &inc(8,$p,$cO);
            &inc_dist($tri,8,$p,$cO);
        }
 
        if ($bound && !defined($entr{"9-$cS-$p-$cO"})) { 
            $entr{"9-$cS-$p-$cO"} = $Ok;
            &inc(9,$cS,$p,$cO);
            &inc_dist($tri,9,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"9-$cS-$p-$cO"})) {
            $entr{"9-$cS-$p-$cO"} = $Ok;
            &inc(9,$cS,$p,$cO);
            &inc_dist($tri,9,$cS,$p,$cO);
        }
    
        print "type=".&KeyID::to_key($cS).", ".
                      &KeyID::to_key($p).", ".&KeyID::to_key($cO)."\n";
    }}}
}

=item C<ok = insert_triple_all($tri)>

Update statistics of the complete schema graph for one triple $tri. 
Compute class identifiers for each component of $tri using properties 
rdf:type, rdfs:subClassOf and rdfs:subPropertyOf. Generate all possible 
schema triples that are the types of $tri. Increment the counters for 
each of the generated schema triples.

=cut
sub insert_triple_all {
    my $tri = shift;

    # print triple
    #print "tri=".&KeyID::to_key($tri->[0]).",".
    #             &KeyID::to_key($tri->[1]).",".
    #             &KeyID::to_key($tri->[2])."\n";

    # calc class idents of S
    my %a1 = ();
    my $pa1 = \%a1;9
    &Kgraph::get_types($tri->[0], $pa1);
    my $sc = &KeyID::to_id("rdfs:subClassOf");
    &Kgraph::close_generalize($pa1, $sc);    

    # calc class idents of P
    my %a2 = ();
    my $pa2 = \%a2;
    $a2{$tri->[1]} = $Ok;  # P is class 
    #&Kgraph::get_types($tri->[1], $pa2);
    my $sp = &KeyID::to_id("rdfs:subPropertyOf");
    &Kgraph::close_generalize($pa2, $sp);    

    # calc class idents of O
    my %a3 = ();
    my $pa3 = \%a3;
    &Kgraph::get_types($tri->[2], $pa3);
    &Kgraph::close_generalize($pa3, $sc);    

    # print sets
    #&Kgraph::set_print("tS=",$pa1);
    #&Kgraph::set_print("tP=",$pa2);
    #&Kgraph::set_print("tO=",$pa3);

    # marking entries 'done'
    my %entr = ();    

    # insert stat for S classes
    my ($cS,$p,$cO) = ();

    # insert stat for SPO classes
    for $cS (keys %{$pa1}) {
    for $p (keys %{$pa2}) {
    for $cO (keys %{$pa3}) {

        if ($bound && !defined($entr{"3-$cS-$p-$cO"})) { 
            $entr{"3-$cS-$p-$cO"} = $Ok;
            &inc(3,$cS,$p,$cO);
            &inc_dist($tri,3,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"3-$cS"})) {
            $entr{"3-$cS"} = $Ok;
            &inc(3,$cS);
            &inc_dist($tri,3,$cS);
        }

        if ($bound && !defined($entr{"4-$cS-$p-$cO"})) { 
            $entr{"4-$cS-$p-$cO"} = $Ok;
            &inc(4,$cS,$p,$cO);
            &inc_dist($tri,4,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"4-$p"})) {
            $entr{"4-$p"} = $Ok;
            &inc(4,$p);
            &inc_dist($tri,4,$p);
        }

        if ($bound && !defined($entr{"5-$cS-$p-$cO"})) { 
            $entr{"5-$cS-$p-$cO"} = $Ok;
            &inc(5                                                                                                   ,$cS,$p,$cO);
            &inc_dist($tri,5,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"5-$cO"})) {
            $entr{"5-$cO"} = $Ok;
            &inc(5,$cO);
            &inc_dist($tri,5,$cO);
        }

        if ($bound && !defined($entr{"6-$cS-$p-$cO"})) { 
            $entr{"6-$cS-$p-$cO"} = $Ok;
            &inc(6,$cS,$p,$cO);
            &inc_dist($tri,6,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"6-$cS-$p"})) {
            $entr{"6-$cS-$p"} = $Ok;
            &inc(6,$cS,$p);
            &inc_dist($tri,6,$cS,$p);
        }

        if ($bound && !defined($entr{"7-$cS-$p-$cO"})) { 
            $entr{"7-$cS-$p-$cO"} = $Ok;
            &inc(7,$cS,$p,$cO);
            &inc_dist($tri,7,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"7-$cS-$cO"})) {
            $entr{"7-$cS-$cO"} = $Ok;
            &inc(7,$cS,$cO);
            &inc_dist($tri,7,$cS,$cO);
        }
  
        if ($bound && !defined($entr{"8-$cS-$p-$cO"})) { 
            $entr{"8-$cS-$p-$cO"} = $Ok;
            &inc(8,$cS,$p,$cO);
            &inc_dist($tri,8,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"8-$p-$cO"})) {
            $entr{"8-$p-$cO"} = $Ok;
            &inc(8,$p,$cO);
            &inc_dist($tri,8,$p,$cO);
        }
 
        if ($bound && !defined($entr{"9-$cS-$p-$cO"})) { 
            $entr{"9-$cS-$p-$cO"} = $Ok;
            &inc(9,$cS,$p,$cO);
            &inc_dist($tri,9,$cS,$p,$cO);
        } elsif (!$bound && !defined($entr{"9-$cS-$p-$cO"})) {
            $entr{"9-$cS-$p-$cO"} = $Ok;
            &inc(9,$cS,$p,$cO);
            &inc_dist($tri,9,$cS,$p,$cO);
        }

    }}}
}

=item C<ok = insert_triple_top($tri,$ul,$ll)>

Update statistics of a strip around the stored schema graph for one 
triple $tri. Compute class identifiers for each component of $tri and 
generate the schema triples $ul levels above and $ll levels below the
stored schema graph. Increment the counters of the selected 
schema triples.

=cut
sub insert_triple_top {
    my $tri = shift;
    my $lv1 = shift;
    my $lv2 = shift;

    # print triple
    #print "---------------------------------------------\n";
    #print "tri=".&KeyID::to_key($tri->[0]).",".
    #             &KeyID::to_key($tri->[1]).",".
    #             &KeyID::to_key($tri->[2])."\n";

    # calc class idents of S
    my %a1 = ();
    my $pa1 = \%a1;
    &Kgraph::get_types($tri->[0], $pa1);
    my $sc = &KeyID::to_id("rdfs:subClassOf");
    &Kgraph::close_generalize($pa1, $sc);    
    #&Kgraph::set_print("pa1(cg)=",$pa1);

    # calc class idents of P
    my %a2 = ();
    my $pa2 = \%a2;
    $a2{$tri->[1]} = $Ok;  # P is class 
    #&Kgraph::get_types($tri->[1], $pa2);
    my $sp = &KeyID::to_id("rdfs:subPropertyOf");
    &Kgraph::close_generalize($pa2, $sp);    
    #&Kgraph::set_print("pa2(cg)=",$pa2);

    # calc class idents of O
    my %a3 = ();
    my $pa3 = \%a3;
    &Kgraph::get_types($tri->[2], $pa3);
    &Kgraph::close_generalize($pa3, $sc);    
    #&Kgraph::set_print("pa3(cg)=",$pa3);

    # sets for S and O
    my %e1 = ();
    my %e3 = ();
    my $pe1 = \%e1;
    my $pe3 = \%e3;
                    
    # sets for classes of S and O
    my %c1 = ();
    my %c3 = ();
    my $pc1 = \%e1;
    my $pc3 = \%e3;
                    
    # loop thru predicates
    my ($cS,$cO,$hd_S,$hd_O,$rc_S,$rc_O);
    my $sc_S = &KeyID::to_id("rdfs:domain");
    my $sc_O = &KeyID::to_id("rdfs:range");
    my $p = $tri->[1];

    # get domains of $p
    $hd_S = &Mstore::open_scan(6,$p,$sc_S);
    do {

        # get next $cS
        if (!defined($hd_S)) {
            # no schema => default
            $cS = &KeyID::to_id("owl:Thing");
        } else {
            # take class of domain of $p
            $rc_S = &Mstore::scan_next($hd_S);
            $cS = $rc_S->[2];
        }
    
        # get ranges of $p and updte stat
        $hd_O = &Mstore::open_scan(6,$p,$sc_O);
        do {

            # get next $cO
            if (!defined($hd_O)) {
                # no schema => default
                $cO = &KeyID::to_id("owl:Thing");
            } else {
                # take class of range of $p
                $rc_O = &Mstore::scan_next($hd_O);
                $cO = $rc_O->[2];
            }
        
            # display type of triple
            #print "typ=".&KeyID::to_key($cS).",".
            #             &KeyID::to_key($p).",".
            #             &KeyID::to_key($cO)."\n";

            # retrieve a strip of $cS up to $lvl1 down to $lvl1
            if (!defined($cach{$cS})) {
                my %c1 = (); 
                $pc1 = \%c1;
                $pc1->{$cS} = $Ok;
                &Kgraph::close_specialize($pc1,$sc,$lv2);
                &Kgraph::set_annotate($pc1,$OOk);
                $pc1->{$cS} = $Ok;
                &Kgraph::close_generalize($pc1,$sc,$lv1);
                #print "created ";
                $cach{$cS} = $pc1;
	    } else {
                #print "cached ";
		$pc1 = $cach{$cS};
	    }
            #&Kgraph::set_print("pc1(csg)=",$pc1);

            # take out from $pa1 to $pe1 classes also in $pc1
            $pe1->{$cS} = $Ok;
            #&Kgraph::set_print("pe1=",$pe1);
            &Kgraph::set_intersect($pa1,$pc1,$pe1);
            #&Kgraph::set_print("pe1(csg)=",$pe1);

            # retrieve a strip of $cO up to $lvl1 down to $lvl1
            if (!defined($cach{$cO})) {
                my %c3 = ();
                $pc3 = \%c3;
                $pc3->{$cO} = $Ok;
                &Kgraph::close_specialize($pc3,$sc,$lv2);
                &Kgraph::set_annotate($pc3,$OOk);
                $pc3->{$cO} = $Ok;
                &Kgraph::close_generalize($pc3,$sc,$lv1);
                #print "created ";
                $cach{$cO} = $pc3;
	    } else {
                #print "cached ";
		$pc3 = $cach{$cO};
	    }
            #&Kgraph::set_print("pc3(csg)=",$pc3);

            # take out from $pa3 to $pe3 classes also in $pc3
            $pe3->{$cO} = $Ok;
            #&Kgraph::set_print("pe3=",$pe3);
            &Kgraph::set_intersect($pa3,$pc3,$pe3);
            #&Kgraph::set_print("pe3(csg)=",$pe3);

        } while (defined($rc_O) && !&Mstore::scan_eor($hd_O)); 
    } while (defined($rc_S) && !&Mstore::scan_eor($hd_S)); 
            
    # marking entries 'done'
    my %entr = ();    

    # print sets
    #&Kgraph::set_print("tS=",$pe1);
    #&Kgraph::set_print("tP=",$pa2);
    #&Kgraph::set_print("tO=",$pe3);

    # go through top sets of S, P and O
    for my $p (keys %a2) {
        for my $s (keys %e1) {
            for my $o (keys %e3) {
                if (!$bound && !defined($entr{"3-$s"})) { 
                    $entr{"3-$s"} = $Ok;
                    &inc(3,$s);
                    &inc_dist($tri,3,$s);
                } elsif ($bound && !defined($entr{"3-$s-$p-$o"})) { 
                    $entr{"3-$s-$p-$o"} = $Ok;
                    &inc(3,$s,$p,$o);
                    &inc_dist($tri,3,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"4-$p"})) { 
                    $entr{"4-$p"} = $Ok;
                    &inc(4,$p);
                    &inc_dist($tri,4,$p);
                } elsif ($bound && !defined($entr{"4-$s-$p-$o"})) { 
                    $entr{"4-$s-$p-$o"} = $Ok;
                    &inc(4,$s,$p,$o);
                    &inc_dist($tri,4,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"5-$o"})) { 
                    $entr{"5-$o"} = $Ok;
                    &inc(5,$o);
                    &inc_dist($tri,5,$o);
                } elsif ($bound && !defined($entr{"5-$s-$p-$o"})) { 
                    $entr{"5-$s-$p-$o"} = $Ok;
                    &inc(5,$s,$p,$o);
                    &inc_dist($tri,5,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"6-$s-$p"})) { 
                    $entr{"6-$s-$p"} = $Ok;
                    &inc(6,$s,$p);
                    &inc_dist($tri,6,$s,$p);
                } elsif ($bound && !defined($entr{"6-$s-$p-$o"})) { 
                    $entr{"6-$s-$p-$o"} = $Ok;
                    &inc(6,$s,$p,$o);
                    &inc_dist($tri,6,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"7-$s-$o"})) { 
                    $entr{"7-$s-$o"} = $Ok;
                    &inc(7,$s,$o);
                    &inc_dist($tri,7,$s,$o);
                } elsif ($bound && !defined($entr{"7-$s-$p-$o"})) { 
                    $entr{"7-$s-$p-$o"} = $Ok;
                    &inc(7,$s,$p,$o);
                    &inc_dist($tri,7,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"8-$p-$o"})) { 
                    $entr{"8-$p-$o"} = $Ok;
                    &inc(8,$p,$o);
                    &inc_dist($tri,8,$p,$o);
                } elsif ($bound && !defined($entr{"8-$s-$p-$o"})) { 
                    $entr{"8-$s-$p-$o"} = $Ok;
                    &inc(8,$s,$p,$o);
                    &inc_dist($tri,8,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"9-$s-$p-$o"})) { 
                    $entr{"9-$s-$p-$o"} = $Ok;
                    &inc(9,$s,$p,$o);
                    &inc_dist($tri,9,$s,$p,$o);
                } elsif ($bound && !defined($entr{"9-$s-$p-$o"})) { 
                    $entr{"9-$s-$p-$o"} = $Ok;
                    &inc(9,$s,$p,$o);
                    &inc_dist($tri,9,$s,$p,$o);
                }
            }
        }
    }
}
 
=item C<ok = insert_triple_top_bckp_1($tri)>

Update statistics for one triple $tri. Compute class identifiers for
each component of $tri by selecting the top level of classes around 
domain and range classes. Increment by one each of the possible key 
classes of triple $tri. (*Obsolete*)

=cut
sub insert_triple_top_bckp_1 {
    my $tri = shift;
    my $lv1 = shift;
    my $lv2 = shift;

    # print triple
    #print "---------------------------------------------\n";
    #print "tri=".&KeyID::to_key($tri->[0]).",".
    #             &KeyID::to_key($tri->[1]).",".
    #             &KeyID::to_key($tri->[2])."\n";

    # calc class idents of S
    my %a1 = ();
    my $pa1 = \%a1;
    &Kgraph::get_types($tri->[0], $pa1);
    my $sc = &KeyID::to_id("rdfs:subClassOf");
    &Kgraph::close_generalize($pa1, $sc);    
    #&Kgraph::set_print("pa1(cg)=",$pa1);

    # calc class idents of P
    my %a2 = ();
    my $pa2 = \%a2;
    $a2{$tri->[1]} = $Ok;  # P is class 
    #&Kgraph::get_types($tri->[1], $pa2);
    my $sp = &KeyID::to_id("rdfs:subPropertyOf");
    &Kgraph::close_generalize($pa2, $sp);    
    #&Kgraph::set_print("pa2(cg)=",$pa2);

    # calc class idents of O
    my %a3 = ();
    my $pa3 = \%a3;
    &Kgraph::get_types($tri->[2], $pa3);
    &Kgraph::close_generalize($pa3, $sc);    
    #&Kgraph::set_print("pa3(cg)=",$pa3);

    # sets for S and O
    my %e1 = ();
    my %e3 = ();
    my $pe1 = \%e1;
    my $pe3 = \%e3;
                    
    # loop thru predicates
    my ($cS,$cO,$hd_S,$hd_O,$rc_S,$rc_O);
    my $sc_S = &KeyID::to_id("rdfs:domain");
    my $sc_O = &KeyID::to_id("rdfs:range");
    my $p = $tri->[1];

    # get domains of $p
    $hd_S = &Mstore::open_scan(6,$p,$sc_S);
    do {

        # get next $cS
        if (!defined($hd_S)) {
            # no schema => default
            $cS = &KeyID::to_id("owl:Thing");
        } else {
            # take class of domain of $p
            $rc_S = &Mstore::scan_next($hd_S);
            $cS = $rc_S->[2];
        }
    
        # get ranges of $p and updte stat
        $hd_O = &Mstore::open_scan(6,$p,$sc_O);
        do {

            # get next $cO
            if (!defined($hd_O)) {
                # no schema => default
                $cO = &KeyID::to_id("owl:Thing");
            } else {
                # take class of range of $p
                $rc_O = &Mstore::scan_next($hd_O);
                $cO = $rc_O->[2];
            }
        
            # update top set for S
            &Kgraph::set_annotate($pe1,$OOk);
            $pe1->{$cS} = $Ok;
            #&Kgraph::set_print("pe1=",$pe1);
            &Kgraph::close_spec_with($pe1,$pa1,$sc,$lv2);
            #&Kgraph::set_print("pe1(csw)=",$pe1);
            &Kgraph::set_annotate($pe1,$OOk);
            $pe1->{$cS} = $Ok;
            &Kgraph::close_gene_with($pe1,$pa1,$sc,$lv1);
            #&Kgraph::set_print("pe1(cgw)=",$pe1);

            # update top set for O
            &Kgraph::set_annotate($pe3,$OOk);
            $pe3->{$cO} = $Ok;
            #&Kgraph::set_print("pe3=",$pe3);
            &Kgraph::close_spec_with($pe3,$pa3,$sc,$lv2);
            #&Kgraph::set_print("pe3(csw)=",$pe3);
            &Kgraph::set_annotate($pe3,$OOk);
            $pe3->{$cO} = $Ok;
            &Kgraph::close_gene_with($pe3,$pa3,$sc,$lv1);
            #&Kgraph::set_print("pe3(cgw)=",$pe3);

        } while (defined($rc_O) && !&Mstore::scan_eor($hd_O)); 
    } while (defined($rc_S) && !&Mstore::scan_eor($hd_S)); 
            
    # marking entries 'done'
    my %entr = ();    

    # print sets
    #&Kgraph::set_print("tS=",$pe1);
    #&Kgraph::set_print("tP=",$pa2);
    #&Kgraph::set_print("tO=",$pe3);

    # go through top sets of S, P and O
    for my $p (keys %a2) {
        for my $s (keys %e1) {
            for my $o (keys %e3) {
                if (!$bound && !defined($entr{"3-$s"})) { 
                    $entr{"3-$s"} = $Ok;
                    &inc(3,$s);
                    &inc_dist($tri,3,$s);
                } elsif ($bound && !defined($entr{"3-$s-$p-$o"})) { 
                    $entr{"3-$s-$p-$o"} = $Ok;
                    &inc(3,$s,$p,$o);
                    &inc_dist($tri,3,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"4-$p"})) { 
                    $entr{"4-$p"} = $Ok;
                    &inc(4,$p);
                    &inc_dist($tri,4,$p);
                } elsif ($bound && !defined($entr{"4-$s-$p-$o"})) { 
                    $entr{"4-$s-$p-$o"} = $Ok;
                    &inc(4,$s,$p,$o);
                    &inc_dist($tri,4,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"5-$o"})) { 
                    $entr{"5-$o"} = $Ok;
                    &inc(5,$o);
                    &inc_dist($tri,5,$o);
                } elsif ($bound && !defined($entr{"5-$s-$p-$o"})) { 
                    $entr{"5-$s-$p-$o"} = $Ok;
                    &inc(5,$s,$p,$o);
                    &inc_dist($tri,5,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"6-$s-$p"})) { 
                    $entr{"6-$s-$p"} = $Ok;
                    &inc(6,$s,$p);
                    &inc_dist($tri,6,$s,$p);
                } elsif ($bound && !defined($entr{"6-$s-$p-$o"})) { 
                    $entr{"6-$s-$p-$o"} = $Ok;
                    &inc(6,$s,$p,$o);
                    &inc_dist($tri,6,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"7-$s-$o"})) { 
                    $entr{"7-$s-$o"} = $Ok;
                    &inc(7,$s,$o);
                    &inc_dist($tri,7,$s,$o);
                } elsif ($bound && !defined($entr{"7-$s-$p-$o"})) { 
                    $entr{"7-$s-$p-$o"} = $Ok;
                    &inc(7,$s,$p,$o);
                    &inc_dist($tri,7,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"8-$p-$o"})) { 
                    $entr{"8-$p-$o"} = $Ok;
                    &inc(8,$p,$o);
                    &inc_dist($tri,8,$p,$o);
                } elsif ($bound && !defined($entr{"8-$s-$p-$o"})) { 
                    $entr{"8-$s-$p-$o"} = $Ok;
                    &inc(8,$s,$p,$o);
                    &inc_dist($tri,8,$s,$p,$o);
                }
                if (!$bound && !defined($entr{"9-$s-$p-$o"})) { 
                    $entr{"9-$s-$p-$o"} = $Ok;
                    &inc(9,$s,$p,$o);
                    &inc_dist($tri,9,$s,$p,$o);
                } elsif ($bound && !defined($entr{"9-$s-$p-$o"})) { 
                    $entr{"9-$s-$p-$o"} = $Ok;
                    &inc(9,$s,$p,$o);
                    &inc_dist($tri,9,$s,$p,$o);
                }
            }
        }
    }
}
 
=item C<ok = insert_triple_top_bckp($tri)>

Update statistics for one triple $tri. Compute class identifiers for
each component of $tri by selecting the top level of classes around 
domain and range classes. Increment by one each of the possible key 
classes of triple $tri. (*Obsolete*)

=cut
sub insert_triple_top_bckp {
    my $tri = shift;
    my $lvl = shift;
    $lvl = 2 if (!defined($lvl));

    # marking entries 'done'
    my %entr = ();    

    # calc class idents of S
    my %a1 = ();
    my $pa1 = \%a1;
    &Kgraph::get_types($tri->[0], $pa1);
    my $sc = &KeyID::to_id("rdfs:subClassOf");
    &Kgraph::close_generalize($pa1, $sc);    

    # calc class idents of P
    my %a2 = ();
    my $pa2 = \%a2;
    $a2{$tri->[1]} = $Ok;  # P is class 
    #&Kgraph::get_types($tri->[1], $pa2);
    my $sp = &KeyID::to_id("rdfs:subPropertyOf");
    &Kgraph::close_generalize($pa2, $sp);    

    # calc class idents of O
    my %a3 = ();
    my $pa3 = \%a3;
    &Kgraph::get_types($tri->[2], $pa3);
    &Kgraph::close_generalize($pa3, $sc);    

    # loop thru predicates
    my ($p,$cS,$cO,$hd_S,$hd_O,$rc_S,$rc_O);
    my $sc_S = &KeyID::to_id("rdfs:domain");
    my $sc_O = &KeyID::to_id("rdfs:range");
    for $p (keys %a2) {

        # get domains of $p
        $hd_S = &Mstore::open_scan(6,$p,$sc_S);
        if (defined $hd_S) {
           do {
              # take class of domain of $p
              $rc_S = &Mstore::scan_next($hd_S);
              $cS = $rc_S->[2];

              # get ranges of $p and updte stat
              $hd_O = &Mstore::open_scan(6,$p,$sc_O);
              if (defined $hd_O) {
                 do {
                    # take class of range of $p
                    $rc_O = &Mstore::scan_next($hd_O);
                    $cO = $rc_O->[2];

                    my %e1 = ();
                    my %e3 = ();
                    my $pe1 = \%e1;
                    my $pe3 = \%e3;
                    
                    # determine top set for S
                    $pe1->{$cS} = $Ok;
		    &Kgraph::close_spec_with($pe1,$pa1,$sc,$lvl);
                    &Kgraph::set_annotate($pe1,$OOk);
                    $pe1->{$cS} = $Ok;
		    &Kgraph::close_gene_with($pe1,$pa1,$sc,10);

                    # determine top set for O
                    $pe3->{$cO} = $Ok;
		    &Kgraph::close_spec_with($pe3,$pa3,$sc,$lvl);
                    &Kgraph::set_annotate($pe3,$OOk);
                    $pe3->{$cO} = $Ok;
		    &Kgraph::close_gene_with($pe3,$pa3,$sc,10);
                    
                    # go through top sets of S and O
                    for $s (keys %e1) {
                        for $o (keys %e3) {
                            if (!defined($entr{"3-$s"})) { 
                                $entr{"3-$s"} = $Ok;
                                &inc(3,$s);
                                &inc_dist($tri,3,$s);
                            }
                            if (!defined($entr{"4-$p"})) { 
                                $entr{"4-$p"} = $Ok;
                                &inc(4,$p);
                                &inc_dist($tri,4,$p);
                            }
                            if (!defined($entr{"5-$o"})) { 
                                $entr{"5-$o"} = $Ok;
                                &inc(5,$o);
                                &inc_dist($tri,5,$o);
                            }
                            if (!defined($entr{"6-$s-$p"})) { 
                                $entr{"6-$s-$p"} = $Ok;
                                &inc(6,$s,$p);
                                &inc_dist($tri,6,$s,$p);
                            }
                            if (!defined($entr{"7-$s-$o"})) { 
                                $entr{"7-$s-$o"} = $Ok;
                                &inc(7,$s,$o);
                                &inc_dist($tri,7,$s,$o);
                            }
                            if (!defined($entr{"8-$p-$o"})) { 
                                $entr{"8-$p-$o"} = $Ok;
                                &inc(8,$p,$o);
                                &inc_dist($tri,8,$p,$o);
                            }
                            if (!defined($entr{"9-$s-$p-$o"})) { 
                                $entr{"9-$s-$p-$o"} = $Ok;
                                &inc(9,$s,$p,$o);
                                &inc_dist($tri,9,$s,$p,$o);
                            }
                        }
                    }
                    #print "type=".&KeyID::to_key($cS).", ".
                    #              &KeyID::to_key($p).", ".&KeyID::to_key($cO)."\n";
                 } while (!&Mstore::scan_eor($hd_O)); 
              }
           } while (!&Mstore::scan_eor($hd_S)); 
        }
    }
}
 
=item C<ok = print_stat()>

Prints statistics by starting with the most populated key pattern
towards least populated classes.

=cut
sub print_stat {
    print "count=".(keys %stat)."\n";
    my @tri = ();

    for $k (sort { $stat{$b} <=> $stat{$a} } (keys %stat)) {

        # compose $id
        @tri = split "-", $k;
        $id = $tri[0]."-".&KeyID::to_key($tri[1]);
        if (defined($tri[2])) {
            $id = "$id-".&KeyID::to_key($tri[2]);
        }
        if (defined($tri[3])) {
            $id = "$id-".&KeyID::to_key($tri[3]);
        }
        # print line
        print "num=".$stat{$k}." key=".$id."\n";
    }
}

=item C<ok = print_stat_count()>

Print counters of instances of schema triples. 

=cut
sub print_stat_count {
    $bound = shift;
    my $bn = "unbound";
    if ($bound) { $bn = "bound"; }
    print "config=ln".(keys %stat).",count,".$bn."\n";
    my @tri = ();
    my ($elm,$cl, $id1, $id2, $id3);
    my @ap = ();

    #for $k (sort { $stat{$b} <=> $stat{$a} } (keys %stat)) {
    for $k (keys %stat) {
        # compose $id
        @tri = split "-", $k;
        $cl = $tri[0];
        $id1 = &KeyID::to_key($tri[1]);
        $id2 = $id3 = undef;
        if (defined($tri[2])) {
            $id2 = &KeyID::to_key($tri[2]);
        }
        if (defined($tri[3])) {
            $id3 = &KeyID::to_key($tri[3]);
        }

        if ($bound) {
            #$elm = "($cl,$id1,$id2,$id3) => ".$stat{$k}."\n";
            if ($cl==3) {
               $elm = "($id1,*$id2*,*$id3*) => ".$stat{$k}."\n";
            } elsif ($cl==4) {        
               $elm = "(*$id1*,$id2,*$id3*) => ".$stat{$k}."\n";
            } elsif ($cl==5 ) {        
               $elm = "(*$id1*,*$id2*,$id3) => ".$stat{$k}."\n";
            } elsif ($cl==6) {        
               $elm = "($id1,$id2,*$id3*) => ".$stat{$k}."\n";
            } elsif ($cl==7) {        
               $elm = "($id1,*$id2*,$id3) => ".$stat{$k}."\n";
            } elsif ($cl==8) {        
               $elm = "(*$id1*,$id2,$id3) => ".$stat{$k}."\n";
            } elsif ($cl==9) {        
               $elm = "($id1,$id2,$id3) => ".$stat{$k}."\n";
            }
            push @ap, ($elm);
        } else {
            if ($cl==3) {
               $elm = "($id1,T,T) => ".$stat{$k}."\n";
            } elsif ($cl==4) {        
               $elm = "(T,$id1,T) => ".$stat{$k}."\n";
            } elsif ($cl==5 ) {        
               $elm = "(T,T,$id1) => ".$stat{$k}."\n";
            } elsif ($cl==6) {        
               $elm = "($id1,$id2,T) => ".$stat{$k}."\n";
            } elsif ($cl==7) {        
               $elm = "($id1,T,$id2) => ".$stat{$k}."\n";
            } elsif ($cl==8) {        
               $elm = "(T,$id1,$id2) => ".$stat{$k}."\n";
            } elsif ($cl==9) {        
               $elm = "($id1,$id2,$id3) => ".$stat{$k}."\n";
            }
            push @ap, ($elm);
        }
    }

    # now print sorted 
    #for $k (sort { ($a =~ s/\*//g) <=> ($b =~ s/\*//g) } @ap) {
    for $k (sort @ap) {
        print $k;
    }
}

=item C<ok = print_stat_distinct()>

Print counters of distinct instances ofschema triples. 

=cut
sub print_stat_distinct {
    my $bound = shift;
    my $bn = "unbound";
    if ($bound) { $bn = "bound"; }
    print "config=ln".(keys %stat1).",dist,".$bn."\n";
    my @tri = ();
    my ($elm,$cl, $id1, $id2, $id3);
    my @ap = ();

    for $k (keys %stat1) {
        # compose $id
        @tri = split "-", $k;
        $cl = $tri[0];
        $id1 = &KeyID::to_key($tri[1]);
        $id2 = $id3 = undef;
        if (defined($tri[2])) {
            $id2 = &KeyID::to_key($tri[2]);
        }
        if (defined($tri[3])) {
            $id3 = &KeyID::to_key($tri[3]);
        }

        if ($bound) {
           #$elm = "($cl,$id1,$id2,$id3) => ".$stat1{$k}."\n";
           if ($cl==3) {
              $elm = "($id1,*$id2*,*$id3*) => ".$stat{$k}."\n";
           } elsif ($cl==4) {        
              $elm = "(*$id1*,$id2,*$id3*) => ".$stat{$k}."\n";
           } elsif ($cl==5 ) {        
              $elm = "(*$id1*,*$id2*,$id3) => ".$stat{$k}."\n";
           } elsif ($cl==6) {        
              $elm = "($id1,$id2,*$id3*) => ".$stat{$k}."\n";
           } elsif ($cl==7) {        
              $elm = "($id1,*$id2*,$id3) => ".$stat{$k}."\n";
           } elsif ($cl==8) {        
              $elm = "(*$id1*,$id2,$id3) => ".$stat{$k}."\n";
           } elsif ($cl==9) {        
              $elm = "($id1,$id2,$id3) => ".$stat{$k}."\n";
           }
           push @ap, ($elm);
        } else {
           if ($cl==3) {
              $elm = "($id1,_,_) => ".$stat1{$k}."\n";
           } elsif ($cl==4) {        
              $elm = "(_,$id1,_) => ".$stat1{$k}."\n";
           } elsif ($cl==5 ) {        
              $elm = "(_,_,$id1) => ".$stat1{$k}."\n";
           } elsif ($cl==6) {        
              $elm = "($id1,$id2,_) => ".$stat1{$k}."\n";
           } elsif ($cl==7) {        
              $elm = "($id1,_,$id2) => ".$stat1{$k}."\n";
           } elsif ($cl==8) {        
              $elm = "(_,$id1,$id2) => ".$stat1{$k}."\n";
           } elsif ($cl==9) {        
              $elm = "($id1,$id2,$id3) => ".$stat1{$k}."\n";
           }
           push @ap, ($elm);
        }
    }

    # now print sorted 
    #for $k (sort { ($a =~ s/\*//g) <=> ($b =~ s/\*//g) } @ap) {
    for $k (sort @ap) {
        print $k;
    }
}

#-------------------------------------------------------------------------------
1;

=back

=head1 AUTHORS

Iztok Savnik <iztok.savnik@upr.si>;
Kiyoshi Nitta <knitta@yahoo-corp.jp>

=head1 DATES 

Created 26/01/2015;
Last update 10/6/2021.

=cut
