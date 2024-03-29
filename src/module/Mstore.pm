=pod

=head1 NAME 

I<Mstore.pm> (v0.1) -- *epsilon* graph store implemented on top of 
BerkeleyDB

=head1 DESCRIPTION

Graph is in *epsilon* store represented as a table C<@stor> storing
edges of a graph in rows. Each edge is defined by triple including
subject node (S), edge name or predicate (P), and, object node
(O). Before entered into table C<@stor> all names of nodes and edges
are converted into integers by means of module L<KeyID.pm>.

Each edge stored as a record in a table @stor has a unique identifier
that allows referencing. Index access to stored graph is provided
using all possible combinations of "keys" that can be the values of S,
P, O, SP, SO, PO and SPO.

Mapping from keys to edge (triple) IDs is realized using an
associative array C<%equi> tied to a BerkeleyDB B-tree. Each key K is
composed of a subset of SPO values comprising a triple. The value part of
this entry includes a reference to the first edge (triple) in table
C<@stor> with a given key value K.

List of edges with a key value K can be accessed by means of a ring of
edges. This is implemented by adding column(s) to C<@stor> that
include references to next edge with a key value K. The table C<@stor>
has therefore 6 additional columns for representation of S, P, O, SP,
SO, PO, and SPO rings.

=cut

package Mstore;

use KeyID;
#use DB_File;
use BerkeleyDB;

=head2 Data structures

=head3 Main-memory graph store

=over 12

=cut
BEGIN {

=item C<$home>

The path to database directory.The default value is "./".
=cut
   $home="~/data/";

=item C<@stor>   

The main table of *epsilon* graph store is in BerkeleyDB implemented
as a table of fixed-length records. The records are accessible via the
record number. Hence, each triple has a triple-id. A triple is stored
in columns 0, 1, 2 of a table @stor. The columns 3,4,5,6,7,8
represent rings for S,P,O,SP,SO,PO,SPO keys, respectively.

=cut
   tie @stor, 'BerkeleyDB::Recno',
                -Cachesize => 800000000,
                -Filename   => "data/base.db",
                -Flags      => DB_CREATE;  #|DB_RDONLY;
   #tie @stor, 'DB_File', "ts/base.db", O_CREAT|O_RDWR, 0777, $DB_RECNO;

=item C<$trcn>

Triple counter.

=cut
   $trcn = scalar(@stor);

=item C<%equi>

A mapping from keys to ids is implemented in a BerkeleyDB B-tree.
A key is composed of:
1. colum num from @stor used for index,
2. first key, and 
3. second key (optional),
4. third key (optional) of the index.

=back

=cut
   tie %equi, 'BerkeleyDB::Btree', 
                -Cachesize => 1000000000,
                -Filename => "data/index.db", 
                -Flags    => DB_CREATE;  # |DB_RDONLY;
#   tie %equi, 'DB_File', "ts/index.db", O_CREAT|O_RDWR, 0777, $DB_HASH;

=head3 Scan access to Mstore

A scan access can be used for accessing rings of a given key.
Scan descriptors are stored in circular array @desc.
Scan descriptors include data about current state of a scan.

=over 12

=item C<@desc>

Circular array of scan descriptors.

=cut
   @desc = ();     

=item C<$dsid>

Current index of scan descriptor.

=cut
   $dsid = 0; 

=item C<$dsnm>

Maximal number of scan descriptors.

=back
=cut
   $dsnm = 9; 
}

=head2 Functions

=over 12

=item C<ok = read(ix)>

Read triple with index ix from @stor into array a. 
Pointer to the array a is returned.

=cut
sub read {
    my $ix = shift;
    my $stored = $stor[$ix];
    my @a = split "\000", $stored;
    return \@a;
}

=item C<ok = write(pa,ix)>

Write array pointed to by parameter pa in @stor at index ix. 

=cut
sub write {
    my $pa = shift;
    my $ix = shift;
    my $stored = join "\000", @{$pa};
    $stor[$ix] = $stored;
    return $Ok;
}

=item C<int = size_store(ix)>

Returns the size of @stor. 

=cut
sub size_store {
    return scalar(@stor);
}

=item C<int = size_index(ix)>

Returns the size of %equi. 

=cut
sub size_index {
    return scalar(keys(%equi));
}

=item C<key = make_key(ix,id,id1,id2)>

Construct key from ix, id, id1, and id2. ix is index that 
identifies the column of @stor (3-9). id, id1 and id2 are index 
values for S,P,O. Function returns the constructed key.

=cut
sub make_key {
    my $ix = shift;    # column index of tuple (of $stor) 
    my $id = shift;    # first key
    my $id1 = shift;   # second key
    my $id2 = shift;   # first key

    # determine key to $equi
    if (defined $id1) {
        if (defined $id2) {
           return "$ix-$id-$id1-$id2";
        } else {
           return "$ix-$id-$id1";
        }
    } else {
        return "$ix-$id";
    }
}

=item C<key = make_keytype(ix,id,id1,id2)>

Construct key type from bu, ix, id, id1, and id2. bu is boolean value 
stating weather counting is bound or unbound. ix is index that 
identifies the column of @stor (3-9). id, id1 and id2 are index 
values for S,P,O. Function returns the constructed key.

=cut
sub make_keytype {
    my $bu = shift;    # bound/unbound
    my $ix = shift;    # column index of tuple (of $stor) 
    my $id = shift;    # first key
    my $id1 = shift;   # second key
    my $id2 = shift;   # first key

    my $ky;
    if ($bu) {
        return "$ix-$id-$id1-$id2";
    } else {
        if (defined $id1) {
            if (defined $id2) {
                return "$ix-$id-$id1-$id2";
            } else {
                return "$ix-$id-$id1";
            }
        } else {
            return "$ix-$id";
        }
    }
}

=item C<kv = make_keyval(tri,ix,id,id1,id2)>

Construct key value kv from triple tri and ix. Insert kv to the statistics 
for given ix and classes id, id1, and id2. 

=cut
sub make_keyval {
    my $tri = shift;   # column index of tuple (of $stor) 
    my $ix = shift;    # column index of tuple (of $stor) 
    #my $id = shift;    # first key
    #my $id1 = shift;   # second key
    #my $id2 = shift;   # first key

    my $ky;
    if    ($ix == 3) { $ky = "$ix-".$tri->[0]; }
    elsif ($ix == 4) { $ky = "$ix-".$tri->[1]; }
    elsif ($ix == 5) { $ky = "$ix-".$tri->[2]; }
    elsif ($ix == 6) { $ky = "$ix-".$tri->[0]."-".$tri->[1]; }
    elsif ($ix == 7) { $ky = "$ix-".$tri->[0]."-".$tri->[2]; }
    elsif ($ix == 8) { $ky = "$ix-".$tri->[1]."-".$tri->[2]; }
    elsif ($ix == 9) { $ky = "$ix-".$tri->[0]."-".$tri->[1]."-".$tri->[2]; }
    return $ky;
}

=item C<key = create_key(ix,k1,k2,k3)>

Construct key from ix, k1, k2, and k3. ix is index that 
identifies the column of @stor (3-9). k1, k2 and k3 are 
string values for S,P,O. Function returns the constructed key.

=cut
sub create_key {
    my $ix = shift;    # column index of tuple (of $stor) 
    my $k1 = shift;    # first part of key
    my $k2 = shift;    # second part of key
    my $k3 = shift;    # first part of key

    my $id1 = &KeyID::to_id($k1);  
    my $id2 = &KeyID::to_id($k2) if (defined $k2);
    my $id3 = &KeyID::to_id($k3) if (defined $k3);

    my $ky;
    if    (($ix == 3) || ($ix == 4) || ($ix == 5)) { $ky = "$ix-".$id1; }
    elsif (($ix == 6) || ($ix == 7) || ($ix == 8)) { $ky = "$ix-".$id1."-".$id2; }
    elsif ($ix == 9) { $ky = "$ix-".$id1."-".$id2."-".$id3; }
    return $ky;
}

=item C<ok = insert_key(ix, id, id1)>

Insert key ix-id[-id1] into key-value table %equi.

=cut
sub insert_key {
    my $pa = shift;    # pointer to triple array
    my $ix = shift;    # column index of tuple (of $stor) 
    my $id = shift;    # first key
    my $id1 = shift;   # second key
    my $id2 = shift;   # first key

    # determine key to $equi
    $id = &make_key($ix,$id,$id1,$id2);

    # insert key $id for tuple $trid into ring
    if (!defined($equi{$id})) {

        # create equi class and enter first tuple
	$equi{$id} = $trcn;
        $pa->[$ix] = $trcn;

    } else {
        # insert $trcn into equi class ring (before first)
        my $eqcl = $equi{$id};
        my $pe = &read($eqcl);
        $pa->[$ix] = $pe->[$ix];
        $pe->[$ix] = $trcn;
        &write($pe,$eqcl);
    }
}

=item C<hd = open_scan(ix, id, id1)>

Open scan for index ix and key(s) id and, optionally, id1.
Return pointer to descriptor.

=cut
sub open_scan {
    my $ix = shift;    # column index of tuple (of $stor) 
    my $id = shift;    # first key
    my $id1 = shift;   # second key
    my $id2 = shift;   # third key

    # determine key to $equi
    $id = &make_key($ix,$id,$id1,$id2);

    # just return if undef
    return undef if (!defined $equi{$id});

    # init scan descriptor
    $desc[$dsid]{ix} = $ix;                  # index of ring 
    $desc[$dsid]{key} = $id;                 # key of scan 
    $desc[$dsid]{six} = $equi{$id};          # index in @store
    $desc[$dsid]{fst} = $desc[$dsid]{six};   # remember first in ring
    $hd = $dsid;                             # store handle
    $dsid = ++$dsid % $dsnm;                 # next $dsid is $dsid+1 modulo $dsnm
    
    # return handle
    return $hd;
}

=item C<$tid = scan_next($hd)>

Return handle ie. index in @desc.

=cut
sub scan_next {
    my $hd = shift;
    
    my $ix = $desc[$hd]{ix};
    my $six = $desc[$hd]{six};
    my $pa = &read($six);
    $desc[$hd]{six} = $pa->[$ix];
    return $pa;
}

=item C<bool = scan_eor($dsix)>

Return true if end of ring and false otherwise.

=cut
sub scan_eor {
    $hd = shift;
    
    return $desc[$hd]{six} == $desc[$hd]{fst};
}

=item C<ok = print_store()>

Prints contents of $stor from 0 to $#stor.

=cut
sub print_store {
    my $bg = shift;
    if (!defined($bg)) { $bg = 0; }
    my $ln = shift;
    if (!defined($ln)) { $ln = $#stor-$bg; }

    # vars
    my ($S,$P,$O);  # triple comps
    my ($iS,$iP,$iO,$iSP,$iSO,$iPO,$iSPO); # indexes
    my $pa; # pntr to trpl
    my $cn = 0;

    for $rid ($bg .. ($bg+$ln)) {
        $cn++;
        $pa = &read($rid);
        $S = &KeyID::to_key($pa->[0]);
        $P = &KeyID::to_key($pa->[1]);
        $O = &KeyID::to_key($pa->[2]);
        $iS = $pa->[3];
        $iP = $pa->[4];
        $iO = $pa->[5];
        $iSP = $pa->[6];
        $iSO = $pa->[7];
        $iPO = $pa->[8];
        $iSPO = $pa->[9];
        print "rid=$rid S=$S P=$P O=$O iS=$iS iP=$iP iO=$iO ".
              "iSP=$iSP iSO=$iSO iPO=$iPO iSPO=$iSPO\n";
#        print "$rid $S $P $O $iS $iP $iO $iSP $iSO $iPO\n";
    }

    print "count=$cn\n";
}

=item C<ok = print_equi(id)>

Prints key-value mapping %equi where key is ix-id-[-id1]
and id is index to @stor.

=cut
sub print_equi {
    my $cnt = 1; # counter
    my ($rid,@key,$dkey);

    for $k (sort keys %equi) {
        $rid = $equi{$k};
        @key = split "-", $k;
        $dkey = $key[0]."-".&KeyID::to_key($key[1]);
        if (defined $key[2]) {
	    $dkey = $dkey."-".&KeyID::to_key($key[2]);
        } 
        if (defined $key[3]) {
	    $dkey = $dkey."-".&KeyID::to_key($key[3]);
        } 
        print "cnt=$cnt key=$dkey rid=$rid\n";
        $cnt++;
    } 
} 

=item C<ok = print_ring(key)>

Prints ring defined by key.

=cut
sub print_ring {
    my $ix = shift;    # column index of tuple (of $stor) 
    my $k1 = shift;    # first part of key
    my $k2 = shift;    # second part of key
    my $k3 = shift;    # third part of key
    my $key = &create_key($ix,$k1,$k2,$k3);

    my ($S,$P,$O);            # triple comps
    my ($iS,$iP,$iO,$iSP,$iSO,$iPO,$iSPO); # indexes
    my $pa; # pntr to trpl

    # get ring entry point $rnep of 
    return undef if (!defined($equi{$key}));
    my $rnep = $equi{$key}; 

    # iterate thru ring
    my $rid = $rnep;
    do {         
        $pa = &read($rid);
        $S = &KeyID::to_key($pa->[0]);
        $P = &KeyID::to_key($pa->[1]);
        $O = &KeyID::to_key($pa->[2]);
        $iS = $pa->[3];
        $iP = $pa->[4];
        $iO = $pa->[5];
        $iSP = $pa->[6];
        $iSO = $pa->[7];
        $iPO = $pa->[8];
        $iSPO = $pa->[9];
        print "rid=$rid S=$S P=$P O=$O iS=$iS iP=$iP iO=$iO ".
              "iSP=$iSP iSO=$iSO iPO=$iPO iSPO=$iSPO\n";
        $rid = $pa->[$ix];
    } until ($rid==$rnep); 
}

=item C<ok = project_ring(key)>

Project ring defined by key into column.

=cut
sub project_ring {
    my $pa = shift;    # column to store result
    my $cl = shift;    # ring column to project
    my $ix = shift;    # column index of tuple (of $stor) 
    my $k1 = shift;    # first part of key
    my $k2 = shift;    # second part of key
    my $k3 = shift;    # third part of key
    my $key = &create_key($ix,$k1,$k2,$k3);
    my $tr;            # pntr to trpl

    # get ring entry point $rnep of 
    return undef if (!defined($equi{$key}));
    my $rnep = $equi{$key}; 

    # iterate thru ring
    my $rid = $rnep;
    do {         
        $tr = &read($rid);
        $vl = $tr->[$cl];
        # print &KeyID::to_key($vl)."\n";
        $pa->{$vl} = 1;
        $rid = $tr->[$ix];

    } until ($rid==$rnep); 
}

=item C<ok = enter_triple($tri)>

Enter triple into KeyID and Mstore.

=cut
sub enter_triple {
    my $tri = shift;   # ref to triple array

    # enter keys to %kyid and @idky to get ids
    &KeyID::enter_key($tri->[0]) if (!&KeyID::isdef($tri->[0]));
    &KeyID::enter_key($tri->[1]) if (!&KeyID::isdef($tri->[1]));
    &KeyID::enter_key($tri->[2]) if (!&KeyID::isdef($tri->[2]));

    # map key list to id list
    my @rec = map { &KeyID::to_id($_) } @$tri;
    
    # insert keys to index %equi
    &insert_key(\@rec,3,$rec[0]);
    &insert_key(\@rec,4,$rec[1]);
    &insert_key(\@rec,5,$rec[2]);
    &insert_key(\@rec,6,$rec[0],$rec[1]);
    &insert_key(\@rec,7,$rec[0],$rec[2]);
    &insert_key(\@rec,8,$rec[1],$rec[2]);
    &insert_key(\@rec,9,$rec[0],$rec[1],$rec[2]);
    &write(\@rec,$trcn);
    $trcn++;
}

#-------------------------------------------------------------------------------
1;

=back

=head1 AUTHORS

Iztok Savnik <iztok.savnik@upr.si>;
Kiyoshi Nitta <knitta@yahoo-corp.jp>

=head1 DATES 

Created 09/12/2014; modified 26/01/2015.

=cut

    

