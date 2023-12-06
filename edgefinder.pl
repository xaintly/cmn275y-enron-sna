#!/usr/bin/perl

# runs through the 'maildir/' folder, extracting all the From:, To:, CC: and BCC: lines from email headers
# exports CSV of from,to,count   with count being the number of times 'from' emailed 'to'

our $CONFIG = {
	# Translating all quoted-printable characters causes problems later with some binary characters, so this is a short list of acceptable ones
	'TRANSLATE_QP'    => { '20' => ' ', '01' => "'", '09' => "\t", '60' => "`", '3D' => '=', '40' => '@' },
};

my $comm_log = {};
recurse_filelist( './maildir', $comm_log ); # collect counts of emails from > to
print_edges( $comm_log ); 

# dump out a hierarchical structure of from > to as a csv
sub print_edges {
  my( $comm_log ) = @_;
  foreach my $from ( sort keys %$comm_log ) {
    next unless $from =~ /^[A-Za-z0-9\.]+$/;
    my $source = $comm_log->{ $from };
    foreach my $to ( sort keys %$source ) {
      next unless $to =~ /^[A-Za-z0-9\.]+$/;
      print join(',', $from, $to, $source->{ $to }),"\n" if $source->{ $to } > 0;
    }
  } 
}

# Identify all the files in the mail folders, recursively descend folder structure
sub recurse_filelist {
  my( $folder, $comm_log ) = @_;

  # get a list of all files in the folder
  opendir( my $dh, $folder ) or die "Can't open $folder, $!";
  my @files = map { $folder . '/' . $_ } grep(!/^\./, readdir( $dh ));
  closedir( $dh );

  foreach my $file ( @files ) {
    if( -d $file ) { recurse_filelist( $file, $comm_log ); }  # If the file is another folder, recurse into it
    else { process_mail( $file, $comm_log ); }
  }
}

# For each file in a mail folder, determine the From:, To:, CC: and Bcc: lines
sub process_mail {
  my( $file, $comm_log ) = @_;

  my $headers = {};
  open( my $fh, '<', $file ) or die "Can't open file $file, $!";
  my $last_header = undef;
  while( my $line = <$fh> ) {
    last if $line =~ /^\s*$/; # email headers end at first blank line
    if( $line =~ /^(\S+):\s*(.*)/ ) { # headers are lines that look like "To: xxxxxx@xxxx" -> "To" = header, "xxxxxx@xxxx" = header data
      my( $header, $value ) = ( lc($1), $2 );  # normalize headers to lowercase
      $value =~ s/\s+$//; # trim trailing space, leading space already removed by regex pattern above
      $last_header = $header;
      $headers->{ $header } = $value; # keep track of the last header we saw since there can be continuation lines
    } elsif( $line =~ /^\s+(\S.*)/ ) { # lines that start with space are continuations of the previous header
      $headers->{ $last_header } .= ' ' . $1; 
    }
  }

  my $from = lc($headers->{'from'} || '');
  return unless $from =~ /(\S+)\@enron\.com/; # discard mail from outside parties
  $from = $1; 
  $from =~ s/^[^A-Za-z0-9_]+//; # cleanup leading space or other non-email characters

  # get a list of unique email targets, considering the to, cc and bcc lines
  my %to = (); # use a hash to eliminate duplicates
  foreach my $target (map { lc($headers->{ $_ } || '') } ('to','cc','bcc')) { # For each possible list of email targets (To:,Cc:,Bcc:)...

	# Decode quoted-printable characters like =20 (space), =40 (@), etc.
	$target =~ s/=\r?\n//gs;
	$target =~ s/=([0-7][0-9A-F])/$CONFIG->{'TRANSLATE_QP'}->{$1} || "=$1"/gse;

    # Now go through the list 	
    while( $target =~ s/(\S+)\@enron\.com// ) { # look email addresses of enron employees [kenneth.lay@enron.com]
      my $target_email = $1;
      $target_email    =~ s/^[^A-Za-z0-9_]+//;
      next if $target_email eq $from; # sometimes people email themselves so ignore these
      $to{ $target_email } = 1; # this ensures that if someone is mentioned multiple times in any of the headers we only count them once
    }
  }

  # increment counts for each from->to pair
  foreach my $target ( keys %to ) {
    $comm_log->{ $from } ||= {};
    $comm_log->{ $from }->{ $target }++;
  }
}
