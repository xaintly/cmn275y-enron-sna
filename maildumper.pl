#!/usr/bin/perl
# Perl, sorry

our $SKIP_SIGNATURES = 0; # Set to 1 to discard email signatures and sign-offs

my $find_email_pattern = $ARGV[0] || die "No pattern";
# print "Looking for [$find_email_pattern]\n";

recurse_filelist( './maildir', $find_email_pattern );

# Descend through the folders of mail, identify message files and inspect them
sub recurse_filelist {
  my( $folder, $pattern ) = @_;
  opendir( my $dh, $folder ) or die "Can't open $folder, $!";
  my @files = map { $folder . '/' . $_ } grep(!/^\./, readdir( $dh ));
  closedir( $dh );

  foreach my $file ( @files ) {
    if( -d $file ) { recurse_filelist( $file, $pattern ); }
    else { process_mail( $file, $pattern ); }
  }
}

# Inspect a message file to see if the requested pattern is found in the From:, To:, CC:, Bcc: lines
sub process_mail {
  my( $file, $pattern ) = @_;

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
    while( $target =~ s/(\S+)\@enron\.com// ) {
      my $target_email = $1;
      $target_email    =~ s/^[^A-Za-z0-9_]+//;
      next if $target_email eq $from;
      $to{ $target_email } = 1;
    }
  }

  # Now that we identified the sender & recipients, see if any of them matches the pattern we are looking for
  my $combined = join(',',$from,keys %to);
  return unless $combined =~ /$pattern/;  # go to next message if not
 
  # Message matches pattern, dump out the message 
  while( my $line = <$fh> ) {
    # Stop printing the message if we get to something that looks like a sign-off or signature
    last if $SKIP_SIGNATURES && $line =~ /^.{1,15},\s*$/; # regards, thanks, best, etc.
    last if $SKIP_SIGNATURES && $line =~ /^-+\s*$/; # regards, thanks, best, etc.
    print $line;
  }

}
