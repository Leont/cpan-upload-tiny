package CPAN::Upload::Tiny;

use strict;
use warnings;

use Carp ();
use File::Basename ();
use File::Spec;
use HTTP::Tiny;
use HTTP::Tiny::Multipart;

my $UPLOAD_URI = $ENV{CPAN_UPLOADER_UPLOAD_URI} || 'https://pause.perl.org/pause/authenquery';

sub new {
	my ($class, $name, $password) = @_;
	return bless {
		name     => $name,
		password => $password,
	}, $class;
}

sub new_from_config {
	my ($class, $filename) = @_;
	my $config = $class->read_config_file($filename);
	bless $config, $class;
}

sub _read_file {
	my $filename = shift;
	open my $fh, '<:raw', $filename or die "Could not open $filename: $!";
	return do { local $/; <$fh> };
}

sub upload_file {
	my ($self, $file) = @_;

	my $tiny = HTTP::Tiny->new();
	my $url = $UPLOAD_URI;
	$url =~ s[//][//$self->{user}:$self->{password}@];
	my $result = $tiny->post_multipart($url, {
		HIDDENNAME => $self->{user},
		CAN_MULTIPART                     => 1,
		pause99_add_uri_httpupload        => {
			filename     => File::Basename::basename($file),
			content      => _read_file($file),
			content_type => 'application/gzip',
		},
		pause99_add_uri_uri               => '',
		SUBMIT_pause99_add_uri_httpupload => " Upload this file from my disk ",
	});

	die "Upload failed: $result->{reason}\n" if !$result->{success};

	return;
}

sub read_config_file {
	my ($class, $filename) = @_;

	if (!defined $filename) {
		$filename = File::Spec->catfile(glob('~'), '.pause');
	}
	die 'Missing configuration file' unless -e $filename and -r _;

	my %conf;
	if ( eval { require Config::Identity } ) {
		%conf = Config::Identity->load($filename);
		$conf{user} = delete $conf{username} unless $conf{user};
	}
	else { # Process .pause manually
		open my $pauserc, '<', $filename or die "can't open $filename for reading: $!";

		while (<$pauserc>) {
			chomp;
			Carp::croak "$filename seems to be encrypted. Maybe you need to install Config::Identity?" if /BEGIN PGP MESSAGE/;

			next if not length or $_ =~ /^\s*#/;

			my ($k, $v) = / ^\s* (\w+) \s+ (.+?) \s* $ /x;
			Carp::croak "Multiple enties for $k" if $conf{$k};
			$conf{$k} = $v;
		}
	}

	return \%conf;
}


1;

#ABSTRACT: A tiny CPAN uploader

=method new($username, $password)

This creates a new C<CPAN::Upload::Tiny> object. It requres a C<$username> and a C<$password>.

=method new_from_config($filename)

This creates a new C<CPAN::Upload::Tiny> based on a F<.pause> configuration file. It will use C<Config::Identity> if available.

=method upload_file($filename)

This uploads the given file to PAUSE/CPAN.
