package main; shift @INC;
#line 1 "script/biber"
#!/usr/local/perl/bin/perl 

eval 'exec /usr/local/perl/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell

use v5.16;
use strict;
use warnings;

use constant {
  EXIT_OK => 0,
  EXIT_ERROR => 2
};

use Carp;
use IPC::Cmd qw( can_run run );
use Log::Log4perl qw(:no_extra_logdie_message);
use Log::Log4perl::Level;
use POSIX qw(strftime);
use Biber;
use Biber::Utils;
use File::Spec;
use Pod::Usage;
use List::AllUtils qw( first );

use Getopt::Long qw/:config no_ignore_case/;
my $opts = {};
GetOptions(
           $opts,
           'bibencoding=s', # legacy alias for input_encoding
           'bblencoding=s', # legacy alias for output_encoding
           'bblsafechars',  # legacy alias for output_safechars
           'bblsafecharsset=s', # legacy alias for output_safecharsset
           'cache',
           'clrmacros',
           'collate|C',
           'collate_options|collate-options|c=s',
           'configfile|g=s',
           'convert_control|convert-control',
           'dot_include|dot-include:s@',
           'decodecharsset=s',
           'debug|D',
           'fastsort|f',
           'fixinits',
           'help|h|?',
           'input_directory|input-directory=s',
           'input_encoding|input-encodinge=s',
           'input_format|input-format=s',
           'listsep=s',
           'logfile=s',
           'mincrossrefs|m=s',
           'namesep=s',
           'noconf',
           'nodieonerror',
           'nolog',
           'nostdmacros',
           'onlylog',
           'others_string|others-string=s',
           'outfile=s',           # legacy alias for output_file
           'outformat=s',         # legacy alias for output_format
           'output_align|output-align',
           'output_directory|output-directory=s',
           'output_encoding|output-encoding|E=s',
           'output_fieldcase|output-fieldcase=s',
           'output_file|output-file|O=s',
           'output_format|output-format=s',
           'output_indent|output-indent=s',
           'output_macro_fields|output-macro-fields=s',
           'output_resolve|output-resolve',
           'output_safechars|output-safechars',
           'output_safecharsset|output-safecharsset=s',
           'quiet|q+',
           'recodedata=s',
           'sortcase=s',
           'sortfirstinits=s',
           'sortlocale|l=s',
           'sortupper=s',
           'ssl-nointernalca',
           'ssl-noverify-host',
           'tool',
           'tool_align|tool-align',                 # legacy alias for output_align
           'tool_config|tool-config',
           'tool_fieldcase|tool-fieldcase=s',       # legacy alias for output_fieldcase
           'tool_indent|tool-indent=s',             # legacy alias for output_indent
           'tool_macro_fields|tool-macro-fields=s', # legacy alias for output_macro_fields
           'tool_resolve|tool-resolve',             # legacy alias for output_resolve
           'trace|T',
           'u',                   # alias for input_encoding=UTF-8
           'U',                   # alias for output_encoding=UTF-8
           'validate_config|validate-config',
           'validate_control|validate-control',
           'validate_datamodel|validate-datamodel|V',
           'version|v',
           'wraplines|w',
           'xsvsep=s',
          ) or pod2usage(-verbose => 0,
                         -exitval => EXIT_ERROR);

# verbose > 1 uses external perldoc, this doesn't work with PAR::Packer binaries
# so use "-noperldoc" to use built-in POD::Text
if (exists $opts->{'help'}) {
  pod2usage(-verbose => 2, -noperldoc => 1, -exitval => EXIT_OK);
}

if (exists $opts->{'version'}) {
  my $v = "biber version: $Biber::Config::VERSION";
  $v .= ' (beta)' if $Biber::Config::BETA_VERSION;
  say "$v";
  exit EXIT_OK;
}

# Show location of PAR::Packer cache
if (exists $opts->{'cache'}) {
  if (my $cache = $ENV{PAR_TEMP}) {
    $cache =~ s|//|/|og; # Sanitise path in case it worries people
    say $cache;
  }
  else {
    say "No cache - you are not running the PAR::Packer executable version of biber";
  }
  exit EXIT_OK;
}

# Show location of default tool mode config file and exit
if (exists $opts->{'tool_config'}) {
  (my $vol, my $dir, undef) = File::Spec->splitpath( $INC{"Biber/Config.pm"} );
  $dir =~ s/\/$//; # splitpath sometimes leaves a trailing '/'
  say File::Spec->catpath($vol, "$dir", 'biber-tool.conf');
  exit EXIT_OK;
}

# Catch this situation early
unless (@ARGV) {
  pod2usage(-verbose => 0,
            -exitval => EXIT_ERROR);
}

# Sanitise collate option if fastsort is specified
if ($opts->{fastsort}) {
  delete $opts->{collate};
}

# Resolve some option shortcuts and legacy aliases
if (my $o = $opts->{tool_align}) {
  $opts->{output_align} = $o;
  delete $opts->{tool_align};
}
if (my $o = $opts->{tool_fieldcase}) {
  $opts->{output_fieldcase} = $o;
  delete $opts->{tool_fieldcase};
}
if (my $o = $opts->{tool_indent}) {
  $opts->{output_indent} = $o;
  delete $opts->{tool_indent};
}
if (my $o = $opts->{tool_macro_fields}) {
  $opts->{output_macro_fields} = $o;
  delete $opts->{tool_macro_fields};
}
if (my $o = $opts->{tool_resolve}) {
  $opts->{output_resolve} = $o;
  delete $opts->{tool_resolve};
}
if (my $o = $opts->{bibencoding}) {
  $opts->{input_encoding} = $o;
  delete $opts->{bibencoding};
}
if (my $o = $opts->{bblencoding}) {
  $opts->{output_encoding} = $o;
  delete $opts->{bblencoding};
}
if (my $o = $opts->{bblsafechars}) {
  $opts->{output_safechars} = $o;
  delete $opts->{bblsafechars};
}
if (my $o = $opts->{bblsafecharsset}) {
  $opts->{output_safecharsset} = $o;
  delete $opts->{bblsafecharsset};
}
if (my $o = $opts->{outfile}) {
  $opts->{output_file} = $o;
  delete $opts->{outfile};
}
if (my $o = $opts->{outformat}) {
  $opts->{output_format} = $o;
  delete $opts->{outformat};
}
if ($opts->{u}) {
  $opts->{input_encoding} = 'UTF-8';
  delete $opts->{u};
}
if ($opts->{U}) {
  $opts->{output_encoding} = 'UTF-8';
  delete $opts->{U};
}

# Check the output_format option
if (my $of = $opts->{output_format}) {
  unless ($opts->{output_format} =~ /\A(?:bbl|dot|bibtex|biblatexml)\z/xms) {
    say STDERR "Biber: Unknown output format '$of', must be one of 'bbl', 'dot', 'bibtex', 'biblatexml'";
    exit EXIT_ERROR;
  }
}

if (exists($opts->{tool}) and
    exists($opts->{output_format}) and
    $opts->{output_format} !~ /\A(?:bibtex|biblatexml)\z/xms) {
    say STDERR "Biber: Output format in tool mode must be one of 'bbl' or 'biblatexml'";
    exit EXIT_ERROR;
}

# Set default output format
if (not exists($opts->{output_format})) {
  if (exists($opts->{tool})) {
    $opts->{output_format} = 'bibtex'; # default for tool mode is different
  }
  else {
    $opts->{output_format} = 'bbl'; # default for normal use
  }
}

# Check the tool_* options
if (exists($opts->{output_indent}) and $opts->{output_indent} !~ /^\d+$/) {
  say STDERR "Biber: Invalid non-numeric argument for 'output_indent' option!";
  exit EXIT_ERROR;
}
if (exists($opts->{output_fieldcase}) and $opts->{output_fieldcase} !~ /^(?:upper|lower|title)$/i) {
  say STDERR "Biber: Invalid argument for 'output_fieldcase' option - must be one of 'upper', 'lower' or 'title'!";
  exit EXIT_ERROR;
}

# Check the dot_include option
if (exists($opts->{dot_include}) and (not exists($opts->{output_format})
                                      or (exists($opts->{output_format}) and
                                          $opts->{output_format} ne 'dot'))) {
  say STDERR "Biber: DOT output format specified but output format is not DOT!";
  exit EXIT_ERROR;
}


if (exists($opts->{dot_include})) {
  $opts->{dot_include} = {map {lc($_) => 1} split(/,/,join(',',@{$opts->{dot_include}}))};
  my @suboptions = ( 'section', 'field', 'crossref', 'xref', 'xdata', 'related' );
  foreach my $g (keys %{$opts->{dot_include}}) {
    unless (first {$_ eq lc($g)} @suboptions) {
      say STDERR "Biber: '$g' is an invalid output type for DOT output";
      exit EXIT_ERROR;
    }
  }
}

# Check input_format option
if (exists($opts->{input_format}) and not exists($opts->{tool}) ) {
  say STDERR "Biber: 'input_format' option is only valid in tool mode";
  exit EXIT_ERROR;
}

if (exists($opts->{input_format}) and
    $opts->{input_format} !~ /^(?:bibtex|biblatexml|)$/i) {
  say STDERR 'Biber: ' . $opts->{input_format} . ' is an invalid input format in tool mode';
  exit EXIT_ERROR;
}


# Create Biber object, passing command-line options
my $biber = Biber->new(%$opts);

# get the logger object
my $logger  = Log::Log4perl::get_logger('main');
my $screen  = Log::Log4perl::get_logger('screen');
my $logfile = Log::Log4perl::get_logger('logfile');

my $outfile;

my $time_string = strftime "%a %b %e, %Y, %H:%M:%S", localtime;
$logfile->info("=== $time_string");

my $bcf = Biber::Config->getoption('bcf');

if (Biber::Config->getoption('output_file')) {
  $outfile = Biber::Config->getoption('output_file')
}
else {
  if (Biber::Config->getoption('tool')) {
    if (Biber::Config->getoption('output_format') eq 'bibtex') { # tool .bib output
      $outfile = $ARGV[0] =~ s/\..+$/_bibertool.bib/r;
    }
    elsif (Biber::Config->getoption('output_format') eq 'biblatexml') { # tool .blxtxml output
      $outfile = $ARGV[0] =~ s/\..+$/_bibertool.bltxml/r;
    }
  }
  else {
    if (Biber::Config->getoption('output_format') eq 'dot') { # .dot output
      $outfile = $bcf =~ s/bcf$/dot/r;
    }
    elsif (Biber::Config->getoption('output_format') eq 'bibtex') { # bibtex output
      $outfile = $bcf =~ s/\..+$/_biber.bib/r;
    }
    elsif (Biber::Config->getoption('output_format') eq 'bbl') { # bbl output
      $outfile = $bcf =~ s/bcf$/bbl/r;
    }
  }
}

# Set the .bbl path to the output dir, if specified
if (my $outdir = Biber::Config->getoption('output_directory')) {
  my (undef, undef, $file) = File::Spec->splitpath($outfile);
  $outfile = File::Spec->catfile($outdir, $file)
}

# Fake some necessary .bcf parts if in tool mode
if (Biber::Config->getoption('tool')) {
  $biber->tool_mode_setup;
}
else {
  # parse the .bcf control file
  $biber->parse_ctrlfile($bcf);
}

# Postprocess biber options now that they are all read from the various places
Biber::Config->postprocess_biber_opts;

# Check to see if the .bcf set debug=1. If so, increase logging level
# We couldn't set this on logger init as the .bcf hadn't been read then
if (Biber::Config->getoption('debug')) {
  $logger->level($DEBUG);
}

if (Biber::Config->getoption('trace')) {
  $logger->trace("\n###########################################################\n",
    "############# Dump of initial config object: ##############\n",
    Data::Dump::pp($Biber::Config::CONFIG), "\n",
    "############# Dump of initial biber object: ###############\n",
    $biber->_stringdump,
    "\n###########################################################")
}

# Set the output class. Should be a subclass of Biber::Output::base
if (Biber::Config->getoption('output_format') eq 'dot') { # .dot output
  require Biber::Output::dot;
  $biber->set_output_obj(Biber::Output::dot->new());
}
else {
  my $package = 'Biber::Output::' . Biber::Config->getoption('output_format');
  eval "require $package" or biber_error("Error loading data source package '$package': $@");
  $biber->set_output_obj(eval "${package}->new()");
}

# Get reference to output object
my $biberoutput = $biber->get_output_obj;

# Set the output target file name
$biberoutput->set_output_target_file($outfile);

# Do all the real work
Biber::Config->getoption('tool') ? $biber->prepare_tool : $biber->prepare;

if (Biber::Config->getoption('trace')) {
  $logger->trace("\n###########################################################\n",
    "############# Dump of final config object: ################\n",
    Data::Dump::pp($Biber::Config::CONFIG), "\n",
    "############# Dump of final biber object: #################\n",
    $biber->_stringdump,
    "\n###########################################################")
}

# Write the output to the target
$biberoutput->output;

$biber->display_problems;

exit EXIT_OK;

__END__

=pod

=encoding utf8

=head1 NAME

C<biber> - A bibtex replacement for users of biblatex

=head1 SYNOPSIS

biber [options] file[.bcf]
biber [options] --tool <datasource>

  Creates "file.bbl" using control file "file.bcf" (".bcf" extension is
  optional). Normaly use with biblatex requires no options as they are
  all set in biblatex and passed via the ".bcf" file

  In "tool" mode (see B<--tool> option), takes a datasource (defaults to
  "bibtex" datasource) and outputs a copy of the datasource with any command-line
  or config file options applied.

  Please run "biber --help" for option details

=head1 DESCRIPTION

C<biber> provides a replacement of the bibtex processor for users of biblatex.

=head1 OPTIONS

=over 4

=item B<--cache>

If running as a PAR::Packer binary, show the cache location and exit.

=item B<--clrmacros>

Clears any BibTeX macros (@STRING) between BibLaTeX refsections. This prevents
BibTeX warnings about macro redefinitions if you are using the same datasource
several times for different refsections.

=item B<--collate|-C>

Sort with C<Unicode::Collate> instead of the built-in sort function.
This is the default.

=item B<--collate-options|-c [options]>

Options to pass to the C<Unicode::Collate> object used for sorting
(default is 'level => "4", variable => "non-ignorable"').
See C<perldoc Unicode::Collate> for details.

=item B<--configfile|-g [file]>

Use F<file> as configuration file for C<biber>.
The default is the first file found among
F<biber.conf> in the current directory, C<$HOME/.biber.conf>,
or else the output of C<kpsewhich biber.conf>.
In tool mode, (B<--tool>) the F<biber-tool.conf> installed with Biber is
always used to set defaults before potentially overriding the defaults with a user-defined
config specified with this option. Use the B<--tool-config> option to view the location of
the default tool mode config file.

=item B<--convert-control>

Converts the F<.bcf> control file into html using an XSLT transform. Can
be useful for debugging. File is named by appending C<.html>
to F<.bcf> file.

=item B<--decodecharsset=[recode set name]>

The set of characters included in the conversion routine when decoding
LaTeX macros into UTF-8 (which happens when B<--bblencoding|-E> is set to
UTF-8). Set to "full" to try harder with a much larger set or "base" to
use a smaller basic set. Default is "base". You may want to try "full"
if you have less common UTF-8 characters in your data source. The recode
sets are defined in the reencoding data file which can be customised.
See the --recodedata option and the PDF manual. The virtual set name "null"
may be specified which effectively turns off macro decoding.

=item B<--debug|-D>

Turn on debugging for C<biber>.

=item B<--dot-include=section,field,xdata,crossref,xref,related>

Specifies the element to include in GraphViz DOT output format if the output format is 'dot'.
You can also choose to display crossref, xref, xdata and/or related entry connections.
The default if not specified is C<--dot_include=section,xdata,crossref,xref>.

=item B<--fastsort|-f>

Use Perl's sort instead of C<Unicode::Collate> for sorting. Also uses
OS locale definitions (which may be broken for some languages ...).

=item B<--fixinits>

Try to fix broken multiple initials when they have no space between them in BibTeX
data sources. That is, "A.B. Clarke" becomes "A. B. Clarke" before name parsing.
This can slightly mess up things like "{U.K. Government}" and other esoteric cases.

=item B<--help|-h>

Show this help message.

=item B<--input-directory [directory]>

F<.bcf> and data files will be looked for first in the F<directory>. See the biber
PDF documentation for the other possibilities and how this interacts with the
C<--output_directory> option.

=item B<--input-encoding|-e [encoding]>

Specify the encoding of the data source file(s). Default is "UTF-8"
Normally it's not necessary to set this as it's passed via the
.bcf file from biblatex's C<bibencoding> option.
See "perldoc Encode::Supported" for a list of supported encodings.
The legacy option B<--bibencoding> is supported as an alias.

=item B<--input-format=bibtex|biblatexml>

Biber input format. This option only means something in tool mode (see B<tool> option) since
normally the input format of a data source is specified in the F<.bcf> file and
therefore from the B<\addbibresouce> macro in BibLaTeX.
The default value when in tool mode is 'bibtex'

=item B<--logfile [file]>

Use F<file.blg> as the name of the logfile.

=item B<--listsep=[sep]>

Use F<sep> as the separator for BibTeX data source list fields. Defaults to BibTeX's usual
'and'.

=item B<--mincrossrefs|-m [number]>

Set threshold for crossrefs.

=item B<--namesep=[sep]>

Use F<sep> as the separator for BibTeX data source name fields. Defaults to BibTeX's usual
'and'.

=item B<--noconf>

Don't look for a configfile.

=item B<--nodieonerror>

Don't exit on errors, just log and continue as far as possible.
This can be useful if the error is something from, for example, the underlying
BibTeX parsing C library which can complain about parsing errors which can be ignored.

=item B<--nolog>

Do not write any logfile.

=item B<--nostdmacros>

Don't automatically define any standard macros like month abbreviations.
If you also define these yourself, this option can be used to suppress
macro redefinition warnings.

=item B<--onlylog>

Do not write any message to screen.

=item B<--others-string=[string]>

Use F<string> as the final name in a name field which implies "et al". Defaults to BibTeX's usual
'others'.

=item B<--output-align>

Align field values in neat columns in output. Effect depends on the output format. Default is true.
The legacy option B<--tool_align> is supported as an alias.

=item B<--output-directory [directory]>

Output files (including log files) are output to F<directory> instead
of the current directory. Input files are also looked for in F<directory>
before current directory (but after C<--input_directory> if that is specified).

=item B<--output-encoding|-E [encoding]>

Specify the encoding of the output C<.bbl> file. Default is "UTF-8".
Normally it's not necessary to set this as it's passed via the
.bcf file from biblatex's C<texencoding> option.
See C<perldoc Encode::Supported> for a list of supported encodings.
The legacy option B<--bblencoding> is supported as an alias.

=item B<--output-indent=[num]>

Indentation for body of entries in output. Effect depends on the output format. Defaults to 2.
The legacy option B<--tool_indent> is supported as an alias.

=item B<--output-fieldcase=upper|lower|title>

Case for field names output. Effect depends on the output format. Defaults to 'upper'.
The legacy option B<--tool_fieldcase> is supported as an alias.

=item B<--output-file|-O [file]>

Output to F<file> instead of F<basename.bbl>
F<file> is relative to B<--output_directory>, if set (absolute
paths in this case are stripped to filename only). F<file> can
be absolute if B<--output_directory> is not set.
The legacy option B<--outfile> is supported as an alias.

=item B<--output-format=dot|bibtex|biblatexml|bbl>

Biber output format. Default if not specified is of course, F<bbl>. Use F<dot>
to output a GraphViz DOT file instead of F<.bbl>. This is a directed graph of
the bibliography data showing entries and, as requested, sections and fields.
You must process this file with C<dot>, e.g. C<dot -Tsvg test.dot -o test.svg> to
render the graph. See the B<--dot_include> option to select what is included in
the DOT output.
The legacy option B<--outformat> is supported as an alias.

=item B<--output-macro-fields=[field1, ... fieldn]>

A comma-separated list of field names whose values are, on output, treated as BibTeX macros.
Effectively this means that they are not wrapped in braces. Effect depends on the output format.
The legacy option B<--tool_macro_fields> is supported as an alias.

=item B<--output-resolve>

Whether to resolve aliases and inheritance (XDATA, CROSSREF etc.) in tool mode. Defaults to 'false'.
The legacy option B<--tool_resolve> is supported as an alias.

=item B<--output-safechars>

Try to convert UTF-8 chars into LaTeX macros when writing the output.
This can prevent unknown char errors when using PDFLaTeX and inputenc
as this doesn't understand all of UTF-8. Note, it is better to switch
to XeTeX or LuaTeX to avoid this situation. By default uses the
--output_safecharsset "base" set of characters.
The legacy option B<--bblsafechars> is supported as an alias.

=item B<--output-safecharsset=[recode set name]>

The set of characters included in the conversion routine for
--output_safechars. Set to "full" to try harder with a much
larger set or "base" to use a basic set. Default is "base" which is
fine for most use cases. You may need to load more macro packages to
deal with the results of "full" (Dings, Greek characters, special
symbols etc.). The recode sets are defined in the reencoding data file which
can be customised. See the --recodedata option and the PDF manual.
The legacy option B<--bblsafecharsset> is supported as an alias. The
virtual set name "null" may be specified which effectively turns off macro encoding.

=item B<--quiet|-q>

Log only errors. If this option is used more than once, don't even log errors.

=item B<--recodedata=[file]>

The data file to use for the reencoding between UTF-8 and LaTeX macros. It defines
the sets specified with the --output_safecharsset and --decodecharsset options.
It defaults to F<recode_data.xml> in the same directory as Biber's F<Recode.pm> module.
See the PDF documentation for the format of this file. If this option is
used, then F<file> should be somewhere C<kpsewhich> can find it.

=item B<--sortcase=true|false>

Case-sensitive sorting (default is true).

=item B<--sortfirstinits=true|false>

When sorting names, use only the first name initials, not full first name. Some people expect
the biblatex B<firstinits> option to do this but it needs to be a separate option in case
users, for example, need to show only initials but sort with full first names (default is false).

=item B<--sortlocale|-l [locale]>

Set the locale to be used for sorting.  With default sorting
(B<--collate|-C>), the locale is used to add CLDR
tailoring to the sort (if available for the locale). With
B<--fastsort|-f> this sets the OS locale for sorting.

=item B<--sortupper=true|false>

Whether to sort uppercase before lowercase when using
default sorting (B<--collate|-C>). When
using B<--fastsort|-f>, your OS collation locale determines
this and this option is ignored (default is true).

=item B<--ssl-nointernalca>

Don't try to use the default Mozilla CA certificates when using HTTPS to fetch remote data.
This assumes that the user will set one of the perl LWP::UserAgent module environment variables
to find the CA certs.

=item B<--ssl-noverify-host>

Turn off host verification when using HTTPS to fetch remote data sources.
You may need this if the SSL certificate is self-signed for example.

=item B<--tool>

Run in tool mode. This mode is datasource centric rather than document centric. biber
reads a datasource (and a config file if specified), applies the command-line and config
file options to the datasource and writes a new datasource. Essentially,
this allows you to change your data sources using biber's transformation options (such as
source mapping, sorting etc.)

=item B<--tool-config>

Show the location of the default tool mode config file and exit. Useful when you need to
copy this file and customise it.

=item B<--trace|T>

Turn on tracing. Also turns on B<--debug|d> and additionally provides a lot of low-level tracing
information in the log.

=item B<-u>

Alias for B<--input_encoding=UTF-8>

=item B<-U>

Alias for B<--output_encoding=UTF-8>

=item B<--validate-config>

Schema validate the biber config file.

=item B<--validate-control>

Schema validate the F<.bcf> biblatex control file.

=item B<--validate-datamodel|-V>

Validate the data against a data model.

=item B<--version|-v>

Display version number.

=item B<--wraplines|-w>

Wrap lines in the F<.bbl> file.

=item B<--xsvsep=[sep]>

Use F<sep> as the separator for fields of format type "xsv" in the data model. A Perl regexp can be specified. Defaults to a single comma surround by optional whitespace (\s*,\s*).

=back

=head1 AUTHOR

François Charette, C<firmicus at ankabut.net>E<10>
Philip Kime, C<Philip at kime.org.uk>

=head1 BUGS & DOCUMENTATION

To see the full documentation, run B<texdoc biber> or get the F<biber.pdf>
manual from SourceForge.

Please report any bugs or feature requests on our Github tracker at
L<https://github.com/plk/biber/issues>.

=head1 COPYRIGHT & LICENSE

Copyright 2009-2015 François Charette and Philip Kime, all rights reserved.

This module is free software.  You can redistribute it and/or
modify it under the terms of the Artistic License 2.0.

This program is distributed in the hope that it will be useful,
but without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut
