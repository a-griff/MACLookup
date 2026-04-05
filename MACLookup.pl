#!/usr/bin/perl
# -------------------------------------------------------
# MACLookup.pl
# Version: 1.0
# -------------------------------------------------------
# Description:
# Lookup manufacturer names based on MAC address prefixes.
# -------------------------------------------------------

use strict;
use warnings;

# ---- SETTINGS ----
my $USE_ONLINE           = 1;
my $CURL_TIMEOUT         = 3;
my $ENABLE_NMAP_LOOKUP   = "y";
my $NMAP_DB              = "/usr/share/nmap/nmap-mac-prefixes";
my $ENABLE_CACHE_FILE    = "y";
my $CACHE_FILE           = "./maclookup.cache";
my $ENABLE_ONLINE_LOOKUP = "y";

# ---- PREFIX DATABASE ----
my @DB = (
    "Amcrest Technologies|9C:8E:CD,A0:60:32",
    "Hangzhou Xiongmai Technology|00:12:10,00:1F:B7,00:1A:1D,00:50:56"
);

# ---- FUNCTIONS ----

sub init_cache {
    return if $ENABLE_CACHE_FILE ne "y";

    if (!-f $CACHE_FILE) {
        open(my $fh, '>', $CACHE_FILE);
        print $fh "# maclookup.cache\n";
        print $fh "# Created by: ./MACLookup.pl\n";
        print $fh "# Purpose: Cache MAC OUI prefix to vendor lookups\n";
        close($fh);
    }

    system("sed -i '/errors/Id' $CACHE_FILE");
}

sub normalize_mac {
    my ($mac) = @_;

    $mac =~ s/[^0-9A-Fa-f]//g;    # remove non-hex
    $mac = uc($mac);              # uppercase

    $mac =~ s/(..)/$1:/g;
    $mac =~ s/:$//;

    return $mac;
}

sub get_prefix {
    my ($mac) = @_;
    my @parts = split(/:/, $mac);
    return join(":", @parts[0..2]);
}

sub lookup_local_db {
    my ($mac) = @_;

    my $best_match = "";
    my $best_len   = 0;

    foreach my $entry (@DB) {
        my ($name, $prefixes) = split(/\|/, $entry);
        my @plist = split(/,/, $prefixes);

        foreach my $p (@plist) {
            $p = uc($p);

            if (index($mac, $p) == 0) {
                my $len = length($p);

                if ($len > $best_len) {
                    $best_len   = $len;
                    $best_match = $name;
                }
            }
        }
    }

    return $best_match if $best_match ne "";
    return;
}

sub lookup_nmap {
    my ($mac) = @_;

    return if $ENABLE_NMAP_LOOKUP ne "y";
    return if !-f $NMAP_DB;

    (my $hex = $mac) =~ s/://g;

    foreach my $len (9, 7, 6) {
        my $key = substr($hex, 0, $len);

        open(my $fh, '<', $NMAP_DB) or return;
        while (my $line = <$fh>) {
            if ($line =~ /^$key\s+/i) {
                $line =~ s/^\S+\s+//;
                chomp($line);
                close($fh);
                return $line;
            }
        }
        close($fh);
    }

    return;
}

sub lookup_cache {
    my ($prefix) = @_;

    return if $ENABLE_CACHE_FILE ne "y";
    return if !-f $CACHE_FILE;

    open(my $fh, '<', $CACHE_FILE) or return;
    while (my $line = <$fh>) {
        if ($line =~ /^$prefix\|(.+)/i) {
            chomp($line);
            close($fh);
            return $1;
        }
    }
    close($fh);

    return;
}

sub lookup_online {
    my ($prefix) = @_;

    return if $ENABLE_ONLINE_LOOKUP ne "y";

    (my $clean = $prefix) =~ s/://g;

    my $cmd = "curl -s --max-time $CURL_TIMEOUT https://api.macvendors.com/$clean";
    my $result = `$cmd`;

    return if $result =~ /errors/i;

    chomp($result);

    if ($ENABLE_CACHE_FILE eq "y") {
        my $exists = 0;

        if (-f $CACHE_FILE) {
            open(my $fh, '<', $CACHE_FILE);
            while (my $line = <$fh>) {
                if ($line =~ /^$prefix\|/i) {
                    $exists = 1;
                    last;
                }
            }
            close($fh);
        }

        if (!$exists) {
            open(my $fh, '>>', $CACHE_FILE);
            print $fh "$prefix|$result\n";
            close($fh);
        }
    }

    return $result;
}

# ---- MAIN ----

if (!defined $ARGV[0]) {
    print "Usage: $0 <MAC1,MAC2,...>\n";
    exit 1;
}

init_cache();

my @macs = split(/,/, $ARGV[0]);

foreach my $rawmac (@macs) {

    my $mac    = normalize_mac($rawmac);
    my $prefix = get_prefix($mac);

    my $found = "";

    $found = lookup_local_db($mac);
    if ($found) {
        print "$mac -> $found\n";
        next;
    }

    $found = lookup_nmap($mac);
    if ($found) {
        print "$mac -> ($found)\n";
        next;
    }

    $found = lookup_cache($prefix);
    if ($found) {
        print "$mac -> ($found)\n";
        next;
    }

    $found = lookup_online($prefix);
    if ($found) {
        print "$mac -> ($found)\n";
    } else {
        print "$mac -> (unknown)\n";
    }
}
