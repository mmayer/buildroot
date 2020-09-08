#!/usr/bin/perl -w

# STB Linux buildroot build system v1.0
# Copyright (c) 2017 Broadcom
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

use strict;
use warnings;
use File::Basename;
use File::Path qw(make_path);
use Getopt::Std;
use POSIX;

use constant AUTO_MK => qw(brcmstb.mk);
use constant LOCAL_MK => qw(local.mk);
use constant RECOMMENDED_TOOLCHAINS => ( qw(misc/toolchain.master
					misc/toolchain) );
use constant SHARED_OSS_DIR => qw(/projects/stbdev/open-source);
use constant TOOLCHAIN_DIR => qw(/opt/toolchains);
use constant VERSION_H => qw(/usr/include/linux/version.h);

use constant SLEEP_TIME => 5;

my %arch_config = (
	'arm64' => {
		'arch_name' => 'aarch64',
		'BR2_aarch64' => 'y',
		'BR2_cortex_a53' => 'y',
		'BR2_LINUX_KERNEL_DEFCONFIG' => 'brcmstb',
	},
	'arm' => {
		'arch_name' => 'arm',
		'BR2_arm' => 'y',
		'BR2_cortex_a15' => 'y',
		'BR2_LINUX_KERNEL_DEFCONFIG' => 'brcmstb',
	},
	'bmips' => {
		'arch_name' => 'mips',
		'BR2_mipsel' => 'y',
		'BR2_MIPS_SOFT_FLOAT' => '',
		'BR2_MIPS_FP32_MODE_32' => 'y',
		'BR2_LINUX_KERNEL_DEFCONFIG' => 'bmips_stb',
		'BR2_LINUX_KERNEL_VMLINUX' => 'y',
	},
);

# It doesn't look like we need to set BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX
# with stbgcc-6.3-x.y, since it has all the required symlinks.
my %toolchain_config = (
	'arm64' => {
#		'BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX' => '$(ARCH)-linux-gnu'
	},
	'arm' => {
#		'BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX' => '$(ARCH)-linux-gnueabihf'
	},
	'bmips' => {
#		'BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX' => '$(ARCH)-linux-gnu'
	},
);

my %generic_config = (
	'BR2_LINUX_KERNEL_CUSTOM_REPO_URL' =>
				'git://stbgit.broadcom.com/queue/linux.git',
	'BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION' => 'stb-4.1',
);

sub check_br()
{
	my $readme = 'README';

	# README file must exist
	return -1 if (! -r $readme);

	open(F, $readme);
	$_ = <F>;
	close(F);

	# First line must contain "Buildroot"
	return 0 if (/Buildroot/);

	return -1;
}

# Check if the shared open source directory exists
sub check_open_source_dir()
{
	return  (-d SHARED_OSS_DIR) ? 1 : 0;
}


# Check if the specified toolchain is the recommended one.
sub check_toolchain($)
{
	my ($toolchain) = @_;
	my $recommended;
	my $found = 0;

	foreach my $tc (RECOMMENDED_TOOLCHAINS) {
		if (open(F, $tc)) {
			$found = 1;
			last;
		}
	}
	# If we don't know what the recommended toolchain is, we accept the
	# one that was specified.
	if (!$found) {
		return '';
	}

	$recommended = <F>;
	chomp($recommended);
	close(F);

	$toolchain =~ s|.*/||;

	return ($recommended ne $toolchain) ? $recommended : '';
}

my @linux_build_artefacts = (
	".config",
	"vmlinux",
	"*.o",
	"vmlinuz",
	"System.map",
);

# Check for some obvious build artifacts that show us the local Linux source
# tree is not clean.
sub check_linux($)
{
	my ($local_linux) = @_;

	foreach (@linux_build_artefacts) {
		return 0 if (-e "$local_linux/$_");
	}

	return 1;
}

sub get_cores()
{
	my $num_cores;

	$num_cores = `getconf _NPROCESSORS_ONLN 2>/dev/null`;
	# Maybe somebody wants to run this on BSD? :-)
	if ($num_cores eq '') {
		$num_cores = `getconf NPROCESSORS_ONLN 2>/dev/null`;
	}
	# Still no luck, try /proc.
	if ($num_cores eq '') {
		$num_cores = `grep -c -P '^processor\\s+:' /proc/cpuinfo 2>/dev/null`;
	}
	# Can't figure out the number of cores. Assume just 1 core.
	if ($num_cores eq '') {
		$num_cores = 1;
	}
	chomp($num_cores);

	return $num_cores;
}

sub find_toolchain()
{
	my @path = split(/:/, $ENV{'PATH'});
	my $dh;

	foreach my $dir (@path) {
		# We don't support anything before stbgcc-6.x at this point.
		if ($dir =~ /stbgcc-[6-9]/) {
			$dir =~ s|/bin/?$||;
			return $dir;
		}
	}

	# If we didn't find a toolchain in the $PATH, we look in the standard
	# location.
	if (opendir($dh, TOOLCHAIN_DIR)) {
		# Sort in reverse order, so newer toolchains appear first.
		my @toolchains = sort { $b cmp $a }
			grep { /stbgcc-[6-9]/ } readdir($dh);

		closedir($dh);

		foreach my $dir (@toolchains) {
			if (-d TOOLCHAIN_DIR."/$dir/bin") {
				return TOOLCHAIN_DIR."/$dir";
			}
		}
	}

	return undef;
}

sub trigger_toolchain_sync($$)
{
	my ($output_dir, $arch) = @_;
	my $path;
	my @files;

	# First, we delete all toolchain symlinks
	$path = "$output_dir/host/bin";
	if (!opendir(D, $path)) {
		return;
	}
	@files = grep { /^$arch/ } readdir(D);
	closedir(D);
	foreach my $f (@files) {
		unlink("$path/$f") if (-l "$path/$f");
	}

	# Secondly, we delete the stamp files, so BR knows to re-sync the
	# toolchain.
	$path = "$output_dir/build/toolchain-external-custom";
	if (!opendir(D, $path)) {
		return;
	}
	@files = grep { /^(\.stamp|.applied)/ } readdir(D);
	closedir(D);
	foreach my $f (@files) {
		unlink("$path/$f");
	}
}

sub get_kernel_header_version($$)
{
	my ($toolchain, $arch) = @_;
	my ($compiler_arch, $sys_root, $version_path);
	my $version_code;

	$compiler_arch = $arch_config{$arch}->{'arch_name'};
	# The MIPS compiler may be called "mipsel-*" not just "mips-*".
	if (defined($arch_config{$arch}->{'BR2_mipsel'})) {
		$compiler_arch .= "el";
	}
	$sys_root = $toolchain;
	$sys_root = `ls -d "$sys_root/$compiler_arch"*/sys*root 2>/dev/null`;
	chomp($sys_root);
	if ($sys_root eq '') {
		return undef;
	}
	$version_path = $sys_root.VERSION_H;

	open(F, $version_path) || return undef;
	while (<F>) {
		chomp;
		if (/LINUX_VERSION_CODE\s+(\d+)/) {
			$version_code = $1;
			last;
		}
	}
	close(F);

	return undef if (!defined($version_code));

	return [($version_code >> 16) & 0xff, ($version_code >> 8) & 0xff];
}

sub move_merged_config($$$$)
{
	my ($prg, $arch, $sname, $dname) = @_;
	my $line;

	open(S, $sname) || die("couldn't open $sname");
	open(D, ">$dname") || die("couldn't create $dname");
	print(D "#" x 78, "\n".
		"# This file was automatically generated by $prg.\n".
		"#\n".
		"# Target architecture: ".uc($arch)."\n".
		"#\n".
		"# ".("-- DO NOT EDIT!!! " x 3)."--\n".
		"#\n".
		"# ".strftime("%a %b %e %T %Z %Y", localtime())."\n".
		"#" x 78, "\n\n");
	while ($line = <S>) {
		chomp($line);
		print(D "$line\n");
	}
	close(D);
	close(S);
	unlink($sname);
}

sub write_localmk($$)
{
	my ($prg, $output_dir) = @_;
	my $local_dest = "$output_dir/".LOCAL_MK;
	my @buf;


	if (open(F, $local_dest)) {
		my $auto_mk = AUTO_MK;

		@buf = <F>;
		close(F);
		# Check if we are already including out auto-generated makefile 
		# snipped. Bail if we do.
		foreach my $line (@buf) {
			return if ($line =~ /include .*$auto_mk/);
		}
	}

	# Add header and include directive for our auto-generated makefile.
	open(F, ">$local_dest");
	print(F "#" x 78, "\n".
		"# The following include was added automatically by $prg.\n".
		"# Please do not remove it. Delete ".AUTO_MK." instead, ".
		"if necessary.\n".
		"# You may also add your own make directives underneath.\n".
		"#" x 78, "\n".
		"#\n".
		"-include $output_dir/".AUTO_MK."\n".
		"#\n".
		"# Custom settings start below.\n".
		"#" x 78, "\n\n");

	# Preserve the contents local.mk had before we started modifying it.
	foreach my $line (@buf) {
		chomp($line);
		print(F $line."\n");
	}

	close(F);
}

sub write_brcmstbmk($$$)
{
	my ($prg, $output_dir, $linux_dir) = @_;
	my $auto_dest = "$output_dir/".AUTO_MK;

	open(F, ">$auto_dest");
	print(F "#" x 78, "\n".
		"# Do not edit. Automatically generated by $prg. It may also ".
		"be deleted\n".
		"# without warning by $prg.\n".
		"#" x 78, "\n".
		"#\n".
		"# You may delete this file manually to remove the settings ".
		"below.\n".
		"#\n".
		"#" x 78, "\n\n".
		"LINUX_OVERRIDE_SRCDIR = $linux_dir\n" .
		"LINUX_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \\\n");
	foreach (@linux_build_artefacts) {
		print(F "\t--exclude=\"$_\" \\\n");
	}
	print(F "\n");
	close(F);
}

sub write_config($$$)
{
	my ($config, $fname, $truncate) = @_;

	unlink($fname) if ($truncate);

	open(F, ">>$fname");
	foreach my $key (keys(%$config)) {
		my $val = $config->{$key};

		# Only write keys that start with BR2_ to config file.
		next if ($key !~ /^BR2_/);

		if ($val eq '') {
			print(F "# $key is not set\n");
			next;
		}

		# Numbers and 'y' don't require quotes. Strings do.
		if ($val ne 'y' && $val !~ /^\d+$/) {
			$val = "\"$val\"";
		}

		print(F "$key=$val\n");
	}
	close(F);
}

sub print_usage($)
{
	my ($prg) = @_;

	print(STDERR "usage: $prg [argument(s)] arm|arm64|bmips\n".
		"          -3 <path>....path to 32-bit run-time\n".
		"          -b...........launch build after configuring\n".
		"          -c...........clean (remove output/\$platform)\n".
		"          -D...........use platform's default kernel config\n".
		"          -d <fname>...use <fname> as kernel defconfig\n".
		"          -f <fname>...use <fname> as BR fragment file\n".
		"          -i...........like -b, but also build FS images\n".
		"          -j <jobs>....run <jobs> parallel build jobs\n".
		"          -L <path>....use local <path> as Linux kernel\n".
		"          -l <url>.....use <url> as the Linux kernel repo\n".
		"          -n...........do not use shared download cache\n".
		"          -o <path>....use <path> as the BR output directory\n".
		"          -t <path>....use <path> as toolchain directory\n".
		"          -v <tag>.....use <tag> as Linux version tag\n");
}

########################################
# MAIN
########################################
my $prg = basename($0);

my $merged_config = 'brcmstb_merged_defconfig';
my $br_output_default = 'output';
my $temp_config = 'temp_config';
my $ret = 0;
my $is_64bit = 0;
my $relative_outputdir;
my $br_outputdir;
my $local_linux;
my $toolchain;
my $recommended_toolchain;
my $kernel_header_version;
my $arch;
my %opts;

getopts('3:bcDd:f:ij:L:l:no:t:v:', \%opts);
$arch = $ARGV[0];

if ($#ARGV < 0) {
	print_usage($prg);
	exit(1);
}

if (check_br() < 0) {
	print(STDERR
		"$prg: must be called from buildroot top level directory\n");
	exit(1);
}

# Treat mips as an alias for bmips.
$arch = 'bmips' if ($arch eq 'mips');
# Are we building for a 64-bit platform?
$is_64bit = ($arch =~ /64/);

if (!defined($arch_config{$arch})) {
	print(STDERR "$prg: unknown architecture $arch\n");
	exit(1);
}

if (defined($opts{'L'}) && defined($opts{'l'})) {
	print(STDERR "$prg: options -L and -l cannot be specified together\n");
	exit(1);
}

# Set local Linux directory from environment, if configured.
if (defined($ENV{'BR_LINUX_OVERRIDE'})) {
	$local_linux = $ENV{'BR_LINUX_OVERRIDE'};
}

# Command line option -L supersedes environment to specify local Linux directory
if (defined($opts{'L'})) {
	# Option "-L -" clears the local Linux directory. This can be used to
	# pretend environment variable BR_LINUX_OVERRIDE is not set, without 
	# having to clear it.
	if ($opts{'L'} eq '-') {
		undef($local_linux);
	} else {
		$local_linux = $opts{'L'};
	}
}

if (defined($local_linux) && !check_linux($local_linux)) {
	print(STDERR "$prg: your local Linux directory must be pristine; ".
		"pre-existing\n".
		"configuration files or build artifacts can interfere with ".
		"the build.\n");
	exit(1);
}

if (defined($opts{'o'})) {
	print("Using ".$opts{'o'}." as output directory...\n");
	$br_outputdir = $opts{'o'};
	$relative_outputdir = $br_outputdir;
} else {
	# Output goes under ./output/ by default. We use an absolute path.
	$br_outputdir = getcwd()."/$br_output_default";
	$relative_outputdir = $br_output_default;
}
# Always add arch-specific sub-directory to output directory.
$br_outputdir .= "/$arch";
$relative_outputdir .= "/$arch";

# Create output directory. "make defconfig" needs it to store $temp_config
# before it would create it itself.
if (! -d $br_outputdir) {
	make_path($br_outputdir);
}

# Our temporary defconfig goes in the output directory.
$temp_config = "$br_outputdir/$temp_config";

if (defined($opts{'c'})) {
	my $status;

	print("Cleaning $br_outputdir...\n");
	$status = system("rm -rf \"$br_outputdir\"");
	$status = ($status >> 8) & 0xff;
	exit($status);
}

$toolchain = find_toolchain();
if (!defined($toolchain) && !defined($opts{'t'})) {
	print(STDERR
		"$prg: couldn't find toolchain in your path, use option -t\n");
	exit(1);
}

if (check_open_source_dir() && !defined($opts{'n'})) {
	my $br_oss_cache = SHARED_OSS_DIR.'/buildroot';

	if (! -d $br_oss_cache) {
		print("Creating shared open source directory $br_oss_cache...\n");
		mkdir($br_oss_cache);
		chmod(0777, $br_oss_cache);
	}

	print("Using $br_oss_cache as download cache...\n");
	$generic_config{'BR2_DL_DIR'} = $br_oss_cache;
}

if (defined($opts{'D'})) {
	print("Using default Linux kernel configuration...\n");
	$arch_config{$arch}{'BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG'} = 'y';
	delete($arch_config{$arch}{'BR2_LINUX_KERNEL_DEFCONFIG'});
}

if (defined($opts{'d'})) {
	my $cfg = $opts{'d'};

	# Make it nice for the user and strip trailing _defconfig.
	$cfg =~ s/_?defconfig$//;
	print("Using $cfg as Linux kernel configuration...\n");
	$arch_config{$arch}{'BR2_LINUX_KERNEL_DEFCONFIG'} = $cfg;
}

if (defined($opts{'j'})) {
	my $jval = $opts{'j'};

	if ($jval !~ /^\d+$/) {
		print(STDERR "$prg: option -j requires an interger argument\n");
		exit(1);
	}
	if ($jval < 1) {
		print(STDERR "$prg: the argument to -j must be 1 or larger\n");
		exit(1);
	}

	if ($jval == 1) {
		print("Disabling parallel builds...\n");
	} else {
		print("Configuring for $jval parallel build jobs...\n");
	}
	$generic_config{'BR2_JLEVEL'} = $jval;
} else {
	$generic_config{'BR2_JLEVEL'} = get_cores() + 1;
}

if (defined($local_linux)) {
	print("Using $local_linux as Linux kernel directory...\n");
	write_brcmstbmk($prg, $relative_outputdir, $local_linux);
	write_localmk($prg, $relative_outputdir);
} else {
	# Delete our custom makefile, so we don't override the Linux directory.
	if (-e "$br_outputdir/".AUTO_MK) {
		unlink("$br_outputdir/".AUTO_MK);
	}
}

if (defined($opts{'l'})) {
	print("Using ".$opts{'l'}." as Linux kernel repo...\n");
	$generic_config{'BR2_LINUX_KERNEL_CUSTOM_REPO_URL'} = $opts{'l'};
}

if (defined($opts{'t'})) {
	$toolchain = $opts{'t'};
}

$recommended_toolchain = check_toolchain($toolchain);
if ($recommended_toolchain ne '') {
	my $t = $toolchain;

	$t =~ s|.*/||;
	print(STDERR "WARNING: you are using toolchain $t. Recommended is ".
		"$recommended_toolchain.\n");
	print(STDERR "Hit Ctrl-C now or wait ".SLEEP_TIME." seconds...\n");
	sleep(SLEEP_TIME);
} else {
	print("Using $toolchain as toolchain...\n");
}
$toolchain_config{$arch}{'BR2_TOOLCHAIN_EXTERNAL_PATH'} = $toolchain;

# The toolchain may have changed since we last configured Buildroot. We need to
# force it to create the symlinks again, so we are sure to use the toolchain
# specified now.
trigger_toolchain_sync($relative_outputdir, $arch);

if (defined($opts{'v'})) {
	print("Using ".$opts{'v'}." as Linux kernel version...\n");
	$generic_config{'BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION'} = $opts{'v'};
}

$kernel_header_version = get_kernel_header_version($toolchain, $arch);
if (defined($kernel_header_version)) {
	my ($major, $minor) = @$kernel_header_version;
	my $ext_headers = "BR2_TOOLCHAIN_EXTERNAL_HEADERS_${major}_${minor}";
	print("Found kernel header version ${major}.${minor}...\n");
	$toolchain_config{$arch}{$ext_headers} = 'y';
} else {
	print("WARNING: couldn't detect kernel header version; build may ".
		"fail\n");
}

if ($is_64bit) {
	my $rt_path;
	my $runtime_base = $toolchain;

	if (defined($opts{'3'})) {
		$rt_path = $opts{'3'};
	} else {
		my $arch32 = $arch;

		$arch32 =~ s|64||;
		# "sysroot" and "sys-root" are being used as directory names
		$rt_path = `ls -d "$runtime_base/$arch32"*/sys*root 2>/dev/null`;
		chomp($rt_path);
	}

	if ($rt_path eq '') {
		print("32-bit libraries not found, disabling 32-bit ".
			"support...\n".
			"Use command line option -3 <path> to specify your ".
			"32-bit sysroot.\n");
	} else {
		my $arch64 = $arch_config{$arch}{'arch_name'};
		my $rt64_path =
			`ls -d "$runtime_base/$arch64"*/sys*root 2>/dev/null`;
		chomp($rt64_path);

		# If "lib64" in the sys-root is a sym-link, we can't build a
		# 64-bit rootfs with 32-bit support. (There's nowhere to put
		# 32-bit libraries.)
		if (-l "$rt64_path/lib64") {
			print("Aarch64 toolchain is not multi-lib enabled. ".
				"Disabling 32-bit support.\n");
		} else {
			print("Using $rt_path for 32-bit environment\n");
			$arch_config{$arch}{'BR2_ROOTFS_RUNTIME32'} = 'y';
			$arch_config{$arch}{'BR2_ROOTFS_RUNTIME32_PATH'} = $rt_path;
		}
	}
}

write_config($arch_config{$arch}, $temp_config, 1);
write_config($toolchain_config{$arch}, $temp_config, 0);
write_config(\%generic_config, $temp_config, 0);

system("support/kconfig/merge_config.sh -m configs/brcmstb_defconfig ".
	"\"$temp_config\"");
if (defined($opts{'f'})) {
	my $fragment_file = $opts{'f'};
	# Preserve the merged configuration from above and use it as the
	# starting point.
	rename('.config', $temp_config);
	system("support/kconfig/merge_config.sh -m $temp_config ".
		"\"$fragment_file\"");
}
unlink($temp_config);
move_merged_config($prg, $arch, ".config", "configs/$merged_config");

# Finalize the configuration by running make ..._defconfig.
system("make O=\"$br_outputdir\" \"$merged_config\"");

print("Buildroot has been configured for ".uc($arch).".\n");
if (defined($opts{'i'})) {
	print("Launching build, including file system images...\n");
	# The "images" target only exists in the generated Makefile in
	# $br_outputdir, so using "make O=..." does not work here.
	$ret = system("make -C \"$br_outputdir\" images");
	$ret >>= 8;
} elsif (defined($opts{'b'})) {
	print("Launching build...\n");
	$ret = system("make O=\"$br_outputdir\"");
	$ret >>= 8;
} else {
	print("To build it, run the following commands:\n".
	"\tcd $br_outputdir; make\n");
}

print(STDERR "$prg: exiting with code $ret\n") if ($ret > 0);
exit($ret);
