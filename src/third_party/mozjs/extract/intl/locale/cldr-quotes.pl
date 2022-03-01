# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Tool to generate the cldr-quotes.inc file, to be #include'd in Quotes.cpp
# to provide locale-appropriate opening and closing quote marks.

# To regenerate cldr-quotes.inc for a new CLDR release, download the data file
# "cldr-common-##.zip" from http://unicode.org/Public/cldr/latest into the
# current directory, update the $filename variable below accordingly, run
#
#   perl cldr-quotes.pl > cldr-quotes.inc
#
# then use `hg diff` to check that the result looks sane.

use warnings;
use strict;

use Encode;
use IO::Uncompress::Unzip;

my $filename = 'cldr-common-36.0.zip';

my (%langQuotes, %quoteLangs);

my $zip = IO::Uncompress::Unzip->new($filename) ||
  die "unzip failed: $IO::Uncompress::Unzip::UnzipError\n";
my $status = 1;
while ($status > 0) {
  my $name = $zip->getHeaderInfo()->{Name};
  if ($name =~ m@common/main/([A-Za-z0-9_]+)\.xml@) {
    my $lang = $1;
    $lang =~ s/_/-/;
    while (<$zip>) {
      $langQuotes{$lang}[0] = $1 if (m!<quotationStart>(.+)<!);
      $langQuotes{$lang}[1] = $1 if (m!<quotationEnd>(.+)<!);
      $langQuotes{$lang}[2] = $1 if (m!<alternateQuotationStart>(.+)<!);
      $langQuotes{$lang}[3] = $1 if (m!<alternateQuotationEnd>(.+)<!);
    }
  }
  $status = $zip->nextStream();
}
$zip->close;

foreach my $lang (sort keys %langQuotes) {
  # We don't actually want to emit anything for the root locale
  next if $lang eq "root";

  # Inherit any missing entries from the locale's parent
  my $parent = $lang;
  while ($parent =~ m/\-/) {
    # Strip off a trailing subtag to find a parent locale code
    $parent =~ s/\-[^-]+$//;
    # Fill in any values available from the parent
    for (my $i = 0; $i < 4; $i++) {
      $langQuotes{$lang}[$i] = $langQuotes{$parent}[$i] unless $langQuotes{$lang}[$i];
    }
  }

  # Anything still missing is copied from the root locale
  for (my $i = 0; $i < 4; $i++) {
    $langQuotes{$lang}[$i] = $langQuotes{"root"}[$i] unless $langQuotes{$lang}[$i];
  }

  # If the locale ends up the same as its parent, skip
  next if ($parent ne $lang) && (exists $langQuotes{$parent}) &&
    (join(",", @{$langQuotes{$lang}}) eq join(",", @{$langQuotes{$parent}}));

  # Create a string with the C source form for the array of 4 quote characters
  my $quoteChars = join(", ", map { sprintf("0x%x", ord Encode::decode("UTF-8", $_)) } @{$langQuotes{$lang}});

  # Record this locale in the list of those which use this particular set of quotes
  $quoteLangs{$quoteChars} = [] unless exists $quoteLangs{$quoteChars};
  push $quoteLangs{$quoteChars}, $lang;
}

# Output each unique list of quotes, with the string of associated locales
my $timestamp = gmtime();
print <<__EOT__;
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/*
 * Derived from the Unicode Common Locale Data Repository by cldr-quotes.pl.
 *
 * For terms of use, see http://www.unicode.org/copyright.html.
 */

/*
 * Created on $timestamp from CLDR data file $filename.
 *
 * * * * * This file contains MACHINE-GENERATED DATA, do not edit! * * * * *
 *
 * (generated by intl/locale/cldr-quotes.pl)
 */

__EOT__

print "static const LangQuotesRec sLangQuotes[] = {\n";
print "  // clang-format off\n";
print sort map { sprintf("  { \"%s\\0\", { { %s } } },\n", join("\\0", sort @{$quoteLangs{$_}}), $_) } (keys %quoteLangs);
print "  // clang-format on\n";
print "};\n";
