#!/usr/bin/perl
# Perl, sorry

use strict; use warnings;

our $CONFIG = {
	'SKIP_SIGNATURES' => 1, # Set to 1 to discard email signatures and sign-offs
	'SKIP_FORWARDS'   => 1, # Set to 1 to discard forwarded or embedded messages
	'MAX_FILE_SIZE'   => 1048000,  # Max bytes for a file uploaded to Amazon Comprehend
	'FOLDER'          => './extracted_mail', 
	'TRANSLATE_QP'    => { '20' => ' ', '01' => "'", '09' => "\t", '60' => "`", '3D' => '=', '40' => '@' },
};


# my $find_email_pattern = $ARGV[0] || die "No pattern";
# print "Looking for [$find_email_pattern]\n";
my $email_stats = {};
foreach my $address ( @ARGV ) {
	my $lc_address = lc($address);
	$email_stats->{ $lc_address } = {
		name => join(' ',map { ucfirst($_) } split(/\./, $lc_address)),
		address => $lc_address,
		file_count_in  => 0,
		file_count_out => 0,
		file_size_in   => 0,
		file_size_out  => 0,
	};
	my $regex_address = $lc_address;
	$regex_address    =~ s/([^A-Za-z0-9])/\\$1/gs;
	$email_stats->{ $lc_address }->{'regex_address'} = $regex_address;
}

my $find_pattern = '(' . join('|', map { $_->{'regex_address'} } values %$email_stats) . ')';
# use Data::Dumper; print Dumper($email_stats); print "FIND [$find_pattern]\n"; 

recurse_filelist( './maildir', $find_pattern, $email_stats );

# Descend through the folders of mail, identify message files and inspect them
sub recurse_filelist {
  my( $folder, $pattern, $stats ) = @_;
  opendir( my $dh, $folder ) or die "Can't open $folder, $!";
  my @files = map { $folder . '/' . $_ } grep(!/^\./, readdir( $dh ));
  closedir( $dh );

  foreach my $file ( @files ) {
    if( -d $file ) { recurse_filelist( $file, $pattern, $stats ); }
    else { process_mail( $file, $pattern, $stats ); }
  }
}

# Inspect a message file to see if the requested pattern is found in the From:, To:, CC:, Bcc: lines
sub process_mail {
  my( $file, $pattern, $stats ) = @_;

  my $headers = {};
  open( my $fh, '<', $file ) or die "Can't open file $file, $!";
  my $last_header = undef;
  while( my $line = <$fh> ) {
    last if $line =~ /^\s*$/; # email message headers end at the first blank line
    if( $line =~ /^(\S+):\s*(.*)/ ) {
      my( $header, $value ) = ( lc($1), $2 );
      $value =~ s/\s+$//;
      $headers->{ $header } = $value;
      $last_header = $header;
    } elsif( $line =~ /^\s+(\S.*)/ ) { # message headers are continued on lines starting with spaces
      $headers->{ $last_header } .= ' ' . $1;
    }
  }

  my $from = lc($headers->{'from'} || '');
  return unless $from =~ /(\S+)\@enron\.com/;
  $from = $1; 
  $from =~ s/^[^A-Za-z0-9_]+//;

  my %to = ();
  foreach my $target (map { lc($headers->{ $_ } || '') } ('to','cc','bcc')) {
	$target =~ s/=\r?\n//gs;
	$target =~ s/=([0-7][0-9A-F])/$CONFIG->{'TRANSLATE_QP'}->{$1} || "=$1"/gse;
    while( $target =~ s/(\S+)\@enron\.com// ) {
      my $target_email = $1;
      $target_email    =~ s/^[^A-Za-z0-9_]+//;
      next if $target_email eq $from;
      $to{ $target_email } = 1;
    }
  }

  # Now that we identified the sender & recipients, see if any of them matches the pattern we are looking for
  my $to_combined  = join(',',keys %to);
  my $all_combined = join(',',$from, $to_combined);
  return unless $all_combined =~ /$pattern/;  # go to next message if not

 
  # Message to/from matches pattern, load message into memory
  my $message_body = '';
  while( my $line = <$fh> ) {
    # Stop printing the message if we get to something that looks like a sign-off or signature
    last if $CONFIG->{'SKIP_SIGNATURES'} && $line =~ /^(.{1,15},|-+)\s*$/; # regards, thanks, best, etc.
    last if $CONFIG->{'SKIP_FORWARDS'}   && $line =~ /^-+\s*(Forwarded by|Original Message)/i; # embedded messages
	$message_body .= $line;
  }
  
  $message_body =~ s/=\r?\n//gs;
  $message_body =~ s/=([0-7][0-9A-F])/$CONFIG->{'TRANSLATE_QP'}->{$1} || "=$1"/gse;
  
  my $message_length = length($message_body);
  
  foreach my $address ( values %$stats ) {
    my $person = $address->{'regex_address'};
	next unless $all_combined =~ /$person/;
	my $box = ( $from =~ /$person/ ) ? 'in' : 'out';
	if( ( $address->{'file_size_' . $box} + $message_length ) > $CONFIG->{'MAX_FILE_SIZE'} ) {
        $address->{'file_count_' . $box}++;
        $address->{'file_size_'  . $box} = 0;
	}
	open(my $fh, ( $address->{'file_size_' . $box} ? '>>' : '>' ), get_filename( $address, $box ));
	print $fh $message_body;
	close( $fh );
	
	$address->{'file_size_'  . $box} += $message_length;
  }
}

sub get_filename {
  my( $stats, $box ) = @_;
  return sprintf('%s/%s-%s-%02d.txt', $CONFIG->{'FOLDER'}, $stats->{'address'}, $box, $stats->{'file_count_' . $box});
}
