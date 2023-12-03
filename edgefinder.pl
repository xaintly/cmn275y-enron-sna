#!/usr/bin/perl

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

# Identify all the files in the mail folders
sub recurse_filelist {
  my( $folder, $comm_log ) = @_;
  opendir( my $dh, $folder ) or die "Can't open $folder, $!";
  my @files = map { $folder . '/' . $_ } grep(!/^\./, readdir( $dh ));
  closedir( $dh );

  foreach my $file ( @files ) {
    if( -d $file ) { recurse_filelist( $file, $comm_log ); }
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
    if( $line =~ /^(\S+):\s*(.*)/ ) { # lines like "To: xxxxxx@xxxx"
      my( $header, $value ) = ( lc($1), $2 );
      $value =~ s/\s+$//;
      $last_header = $header;
      $headers->{ $header } = $value;
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
  foreach my $target (map { lc($headers->{ $_ } || '') } ('to','cc','bcc')) {
    while( $target =~ s/(\S+)\@enron\.com// ) { # don't care about anyone not at enron
      my $target_email = $1;
      $target_email    =~ s/^[^A-Za-z0-9_]+//;
      next if $target_email eq $from;
      $to{ $target_email } = 1;
    }
  }

  # increment counts for each from->to pair
  foreach my $target ( keys %to ) {
    $comm_log->{ $from } ||= {};
    $comm_log->{ $from }->{ $target }++;
  }
}
