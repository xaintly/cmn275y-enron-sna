#!/usr/bin/perl

# Arguments: edgefilter.pl filename min_count user [user ...]
#    filename  -> name of CSV file with source,target,msg_count  (eg. output of edgefinder.pl)
#    min_count -> discard edges with fewer than this many emails
#    user      -> user IDs eg: kenneth.lay

# if you have a list of users in a file and want all edges with a minimum count of 10, you can do 
#     cat userlist.txt | xargs ./edgefilter exported_edges.csv 10 

use strict; use warnings;

my( $file, $min_count, @users ) = @ARGV; # get arguments

# Convert user list to regex, escaping special characters
foreach my $user ( @users ) { $user =~ s/(\W)/\\$1/g; }
my $regex = '(' . join('|', @users) . ')';
# print "Looking for " . $regex, "\n";

# Look through file...
open( my $fh, '<', $file ) or die "Can't, $!";
while( my $line = <$fh> ) {
	next unless $line =~ /$regex/;  # skip if no matching users
	chomp $line;
	my( $to, $from, $count ) = split(/,/, $line);
	next unless $count >= $min_count;  # skip if fewer than min_count users
	print $line,"\n"; # output line if criteria are met
}
close( $fh );
