=pod

=head1 NAME 

I<KeyID.pm> (v0.1) -- mapping between RDF symbols (keys) and ids. 

=head1 DESCRIPTION

Module I<KeyID.pm> implements a mapping between RDF keys and unique
identifiers.

=cut

package KeyID;

use DB_File;
use BerkeleyDB;

=head2 Data structures

=over 12

=cut
BEGIN {

=item I<%kyid>

Mapping from keys to ids.

=cut
   # tie %kyid, 'DB_File', "ts/kyid.db", O_CREAT|O_RDWR, 0777, $DB_HASH;
   tie %kyid, 'BerkeleyDB::Btree', 
                -Cachesize => 300000000,
                -Filename  => "data/kyid.db", 
                -Flags     => DB_CREATE; #|DB_RDONLY;

=item I<@idky>

Mapping from ids to keys.

=cut
   # tie @idky, 'DB_File', "ts/idky.db", O_CREAT|O_RDWR, 0777, $DB_RECNO;
   tie @idky, 'BerkeleyDB::Recno',
                -Cachesize  => 300000000,
                -Filename   => "data/idky.db",
                -Flags      => DB_CREATE; #|DB_RDONLY;

=item I<$kycn>

Counter of keys.

=back

=cut
   $kycn = scalar(@idky); 
}

=head1 Functions

=over 12

=item C<ok = enter_key(ky)>

Enters a key $ky to tables %kyid and @idky.
$kycn represents an id of a key.

=cut
sub enter_key {
    $ky = shift;

    # enter ky with id 
    $kyid{$ky} = $kycn;
    $idky[$kycn] = $ky;
    $kycn++;
}

=item C<bool = isdef(ky)>

Returns true if a key $ky exists in %kyid and false otherwise.

=cut
sub isdef {
    $ky = shift;
    return defined($kyid{$ky});
}

=item C<id = to_id(ky)>

Maps a key $ky to an id $id.

=cut
sub to_id {
    $ky = shift;
    return $kyid{$ky};
}

=item C<ky = to_key(id)>

Maps an id $id to a key $ky.

=cut
sub to_key {
    $id = shift;
    return $idky[$id];
}

#-------------------------------------------------------------------------------
1;

=back

=head1 AUTHORS

Iztok Savnik <iztok.savnik@upr.si>;
Kiyoshi Nitta <knitta@yahoo-corp.jp>

=head1 DATES 

Created 09/12/2014; modified 26/01/2015; Last update 10/6/2021.

=cut
