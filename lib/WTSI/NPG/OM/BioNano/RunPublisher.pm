package WTSI::NPG::OM::BioNano::RunPublisher;

use Moose;
use namespace::autoclean;
use sigtrap qw(die untrapped normal-signals
               stack-trace any error-signals);
# sigtrap ensures cleanup of temporary directory on unexpected exit

use DateTime;
use File::Basename qw[basename];
use File::Spec::Functions;
use File::Temp qw[tempdir];
use URI;

use WTSI::DNAP::Utilities::Runnable;
use WTSI::DNAP::Warehouse::Schema;
use WTSI::NPG::iRODS;
use WTSI::NPG::iRODS::Collection;
use WTSI::NPG::iRODS::DataObject;
use WTSI::NPG::iRODS::Metadata;
use WTSI::NPG::HTS::Publisher;
use WTSI::NPG::OM::BioNano::ResultSet;

# FIXME Move/refactor WTSI::NPG::HTS::Publisher to reflect use outside of
# HTS. Maybe consolidate with WTSI::NPG::Publisher in wtsi-npg/genotyping.

our $VERSION = '';

our @BNX_SUFFIXES = qw[bnx];
our $TAR_SUFFIX = '.tar';
our $GZIP_SUFFIX = '.gz';
our $PIGZ_PROCESSES = 4;

with qw[WTSI::DNAP::Utilities::Loggable
        WTSI::NPG::Accountable
        WTSI::NPG::OM::BioNano::Annotator];

has 'directory' =>
  (is       => 'ro',
   isa      => 'Str',
   required => 1,
   documentation => 'Path of a BioNano runfolder to be published'
);

has 'irods' =>
  (is       => 'ro',
   isa      => 'WTSI::NPG::iRODS',
   required => 1,
   default  => sub {
     return WTSI::NPG::iRODS->new;
   });

has 'mlwh_schema' =>
  (is            => 'ro',
   isa           => 'WTSI::DNAP::Warehouse::Schema',
   required      => 1,
   documentation => 'A ML warehouse handle to obtain secondary metadata');

has 'resultset' =>
  (is       => 'ro',
   isa      => 'WTSI::NPG::OM::BioNano::ResultSet',
   init_arg => undef,
   lazy     => 1,
   builder  => '_build_resultset',
   documentation => 'Object containing results from a BioNano runfolder'
);

#also has uuid attribute from WTSI::NPG::OM::BioNano::Annotator


=head2 publish

  Arg [1]    : [Str] iRODS path that will be the root destination for
               publication. BioNano will be published to a subcollection,
               with a hashed path based on the md5 checksum of the
               Molecules.bnx file.
  Arg [2]    : [DateTime] Timestamp for the time of publication. Optional,
               defaults to the present time.

  Example    : $export->publish('/foo')
  Description: Publish the BioNano ResultSet to an iRODS path.
  Returntype : True

=cut

sub publish {
    my ($self, $publish_dest, $timestamp) = @_;
    # generate a hashed path for publication
    if (! file_name_is_absolute($publish_dest)) {
        $self->logcroak(q[An absolute destination path is required for ],
                        q[iRODS publication; given path was '],
                        $publish_dest, q['])
    }
    if (! defined $timestamp) {
        $timestamp = DateTime->now();
    }
    my $hash_path =
        $self->irods->hash_path($self->resultset->filtered_bnx_path,
                                $self->resultset->bnx_file->md5sum);
    $self->debug(q[Found hashed path '], $hash_path, q[' from checksum '],
                 $self->resultset->bnx_file->md5sum, q[']);
    my $leaf_collection = catdir($publish_dest, $hash_path);
    $self->debug(q[Publishing to collection '], $leaf_collection, q[']);
    # compress to .tar.gz format & publish to iRODS, if not already present
    my $dirname = basename($self->resultset->directory);
    my $filename = $dirname.$TAR_SUFFIX.$GZIP_SUFFIX;
    my $bionano_path = catfile($leaf_collection, $filename);
    if ($self->irods->list_object($bionano_path)) {
        $self->info(q[Skipping publication of BioNano data object '],
                $bionano_path, q[': already exists]);
    } else {
        my @stock_records = $self->_query_ml_warehouse();
        my @collection_meta = $self->make_collection_metadata(
            $self->resultset,
            @stock_records,
        );
        my $publisher = WTSI::NPG::HTS::Publisher->new(irods => $self->irods);
        my $tmp_archive_path = $self->_write_temporary_archive();
        my $bionano_published_obj = $publisher->publish(
            $tmp_archive_path,
            $bionano_path,
            \@collection_meta,
            $timestamp,
        );
        if ($bionano_published_obj ne $bionano_path) {
            $self->logcroak(q[Expected BioNano publication destination '],
                            $bionano_path,
                            q[' not equal to return value from Publisher '],
                            $bionano_published_obj, q[']
                        );
        } else {
            $self->debug(q[Published BioNano runfolder '],
                         $self->resultset->directory,
                         q[' to iRODS destination '],
                         $bionano_path, q[']
                     );
        }
    }
    return $bionano_path;
}

sub _build_resultset {
    my ($self,) = @_;
    my $resultset = WTSI::NPG::OM::BioNano::ResultSet->new(
        directory => $self->directory
    );
    return $resultset;
}

sub _query_ml_warehouse {
    # query the multi-LIMS warehouse to get BioNano StockResource results
    # use these to get sample and study information
    my ($self,) = @_;
    my $stock_id = $self->resultset->stock;
    my @stock_records = $self->mlwh_schema->resultset('StockResource')->search
        ({id_stock_resource_lims => $stock_id, },
         {prefetch                  => ['sample', 'study']});
    my $stock_total = scalar @stock_records;
    if ($stock_total == 0) {
        $self->logwarn('Did not find any results in ML Warehouse for ',
                       q[stock ID '], $stock_id, q[']);
    } else {
        $self->info('Found ', $stock_total, ' result(s) in ML Warehouse ',
                    q[for stock ID '], $stock_id, q[']);
    }
    return @stock_records;
}

sub _write_temporary_archive {
    # write a temporary .tar.gz file for publication to iRODS
    # .tar.gz file contains all BNX and ancillary file paths from ResultSet
    # first archive with tar, then compress with pigz for greater speed
    my ($self,) = @_;
    my $tmp = tempdir('bionano_publish_XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $tarname = basename($self->resultset->directory).$TAR_SUFFIX;
    my $tarpath = catfile($tmp, $tarname);
    my @files;
    push @files, @{$self->resultset->bnx_paths};
    push @files, @{$self->resultset->ancillary_file_paths};
    # write tar inputs to a file; sidesteps issues with spaces in filenames
    my $listpath = catfile($tmp, 'filenames.txt');
    open my $out, '>', $listpath ||
        $self->logcroak(q[Cannot open temporary file '], $listpath, q[']);
    foreach my $file (@files) {
        print $out $file."\n" || $self->logcroak(q[Failed writing string '],
                                                 $file,
                                                 q[' to temporary file '],
                                                 $listpath, q[']);
    }
    close $out ||
        $self->logcroak(q[Cannot close temporary file '], $listpath, q[']);
    WTSI::DNAP::Utilities::Runnable->new(
        executable => 'tar',
        arguments  => ['-c', '-f', $tarpath, '-T', $listpath],
    )->run();
    WTSI::DNAP::Utilities::Runnable->new(
        executable => 'pigz',
        arguments  => ['-p', $PIGZ_PROCESSES, $tarpath],
    )->run();
    my $gztarpath = $tarpath.$GZIP_SUFFIX;
    if (! -e $gztarpath) {
        $self->logcroak(q[Temporary archive path '],
                        $gztarpath, q[' does not exist]);
    } else {
        $self->debug(q[Created temporary archive path '], $gztarpath, q[']);
    }
    return $gztarpath;
}


__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=head1 NAME

WTSI::NPG::OM::BioNano::RunPublisher - An iRODS data publisher
for results from the BioNano optical mapping system.

=head1 SYNOPSIS

  my $publisher = WTSI::NPG::OM::BioNano::RunPublisher->new
    (directory        => $dir,
     irods            => $irods_handle,
     accountee_uid    => $accountee_uid,
     affiliation_uri  => $affiliation_uri,
    );

  # Publish to iRODS with a given timestamp
  $publisher->publish($publish_dest, $timestamp);


=head1 DESCRIPTION

This class provides methods for publishing a BioNano unit runfolder to
iRODS, with relevant metadata, in the form of a compressed TAR file. Any
TIFF image files present in the runfolder are omitted from iRODS publication.
The tree rooted at the runfolder path must contain exactly one filtered BNX
file, named Molecules.bnx.

The "unit" runfolder contains data from one run on the BioNano instrument,
with a given sample, flowcell, and chip. The results of multiple runs are
typically merged together for downstream analysis and assembly.

=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2016, 2017 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.


=cut
