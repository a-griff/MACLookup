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
my $USE_ONLINE            = 1;
my $CURL_TIMEOUT          = 3;
my $ENABLE_NMAP_LOOKUP    = "y";   # <"y/n">
my $NMAP_DB               = "/usr/share/nmap/nmap-mac-prefixes";
my $ENABLE_CACHE_FILE     = "y";   # <"y/n">
my $CACHE_FILE            = "./maclookup.cache";
my $ENABLE_ONLINE_LOOKUP  = "y";   # <"y/n">

# ---- PREFIX DATABASE ----
my @DB = (
    "Amcrest Technologies|9C:8E:CD,A0:60:32",
    "Thingino(Cinnado)|02:07:25"
);

# ---- FUNCTIONS ----

sub show_usage {
    print <<"EOF";
USAGE:
  $0 <MAC1,MAC2,...>

DESCRIPTION:
  Lookup vendor names from MAC addresses using:
    1) Local prefix database
    2) Nmap database (if enabled)
    3) Cache file (if enabled)
    4) Online lookup (if enabled)

EXAMPLE:
  $0 9C:8E:CD:27:0C:B3,A0:60:32:03:61:33
EOF
}

sub init_cache {
    return if $ENABLE_CACHE_FILE ne "y";

    if ( ! -f $CACHE_FILE ) {
        open(my $fh, ">", $CACHE_FILE) or return;
        print $fh "# maclookup.cache\n";
        print $fh "# Created by: ./MACLookup.pl\n";
        print $fh "# Purpose: Cache MAC OUI prefix to vendor lookups\n";
        close($fh);
    }

    # remove lines containing "errors"
    system("sed -i '/errors/Id' $CACHE_FILE");
}

sub normalize_mac {
    my ($mac) = @_;
    return uc($mac);
}

sub get_prefix {
    my ($mac) = @_;
    my @parts = split(/:/, $mac);
    return join(":", @parts[0..2]);
}

sub lookup_local_db {
    my ($prefix) = @_;

    foreach my $entry (@DB) {
        my ($name, $plist) = split(/\|/, $entry);
        my @prefixes = split(/,/, $plist);

        foreach my $p (@prefixes) {
            if ($prefix eq $p) {
                return $name;
            }
        }
    }
    return "";
}

sub lookup_nmap {
    my ($mac) = @_;

    return "" if ($ENABLE_NMAP_LOOKUP ne "y");
    return "" if (! -f $NMAP_DB);

    my $hex = $mac;
    $hex =~ s/://g;

    foreach my $len (9, 7, 6) {
        my $key = substr($hex, 0, $len);

        open(my $fh, "<", $NMAP_DB) or next;
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

    return "";
}

sub lookup_cache {
    my ($prefix) = @_;

    return "" if ($ENABLE_CACHE_FILE ne "y");
    return "" if (! -f $CACHE_FILE);

    open(my $fh, "<", $CACHE_FILE) or return "";
    while (my $line = <$fh>) {
        if ($line =~ /^$prefix\|(.+)/i) {
            chomp($line);
            close($fh);
            return $1;
        }
    }
    close($fh);

    return "";
}

sub lookup_online {
    my ($prefix) = @_;

    return "" if ($ENABLE_ONLINE_LOOKUP ne "y");

    my $clean = $prefix;
    $clean =~ s/://g;

    my $cmd = "curl -s --max-time $CURL_TIMEOUT https://api.macvendors.com/$clean";
    my $result = `$cmd`;

    return "" if ($result =~ /errors/i);

    chomp($result);

    # cache it
    if ($ENABLE_CACHE_FILE eq "y") {
        my $exists = 0;

        if (-f $CACHE_FILE) {
            open(my $fh, "<", $CACHE_FILE);
            while (my $line = <$fh>) {
                if ($line =~ /^$prefix\|/i) {
                    $exists = 1;
                    last;
                }
            }
            close($fh);
        }

        if (!$exists) {
            open(my $fh, ">>", $CACHE_FILE);
            print $fh "$prefix|$result\n";
            close($fh);
        }
    }

    return $result;
}

# ---- MAIN ----

# Help flags
if (defined $ARGV[0] && $ARGV[0] =~ /^(-h|--help|-\?)$/) {
    show_usage();
    exit 0;
}

if (!defined $ARGV[0]) {
    show_usage();
    exit 1;
}

init_cache();

my @macs = split(/,/, $ARGV[0]);

foreach my $raw (@macs) {

    my $mac    = normalize_mac($raw);
    my $prefix = get_prefix($mac);
    my $found  = "";

    # 1. Local
    $found = lookup_local_db($prefix);
    if ($found ne "") {
        print "$mac -> $found\n";
        next;
    }

    # 2. Nmap
    $found = lookup_nmap($mac);
    if ($found ne "") {
        print "$mac -> ($found)\n";
        next;
    }

    # 3. Cache
    $found = lookup_cache($prefix);
    if ($found ne "") {
        print "$mac -> ($found)\n";
        next;
    }

    # 4. Online
    $found = lookup_online($prefix);
    if ($found ne "") {
        print "$mac -> ($found)\n";
    } else {
        print "$mac -> (unknown)\n";
    }
}
