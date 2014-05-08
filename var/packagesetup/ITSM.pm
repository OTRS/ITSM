# --
# ITSM.pm - code to excecute during package installation
# Copyright (C) 2001-2014 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package var::packagesetup::ITSM;    ## no critic

use strict;
use warnings;

use Kernel::System::Package;
use Kernel::System::SysConfig;

=head1 NAME

ITSM.pm - code to excecute during package installation

=head1 SYNOPSIS

All functions

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::DB;
    use Kernel::System::Main;
    use Kernel::System::Time;
    use var::packagesetup::ITSM;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject    = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $TimeObject = Kernel::System::Time->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $CodeObject = var::packagesetup::ITSM->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
        TimeObject   => $TimeObject,
        DBObject     => $DBObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Object (qw(ConfigObject EncodeObject LogObject MainObject TimeObject DBObject)) {
        $Self->{$Object} = $Param{$Object} || die "Got no $Object!";
    }

    # create needed sysconfig object
    $Self->{SysConfigObject} = Kernel::System::SysConfig->new( %{$Self} );

    # rebuild ZZZ* files
    $Self->{SysConfigObject}->WriteDefault();

    # define the ZZZ files
    my @ZZZFiles = (
        'ZZZAAuto.pm',
        'ZZZAuto.pm',
    );

    # reload the ZZZ files (mod_perl workaround)
    for my $ZZZFile (@ZZZFiles) {

        PREFIX:
        for my $Prefix (@INC) {
            my $File = $Prefix . '/Kernel/Config/Files/' . $ZZZFile;
            next PREFIX if !-f $File;
            do $File;
            last PREFIX;
        }
    }

    # create additional objects
    $Self->{PackageObject} = Kernel::System::Package->new( %{$Self} );

    # define path to the packages
    $Self->{PackagePath} = '/var/packagesetup/ITSM/';

    # define package names
    $Self->{PackageNames} = [
        'GeneralCatalog',
        'ITSMCore',
        'ITSMIncidentProblemManagement',
        'ITSMConfigurationManagement',
        'ITSMChangeManagement',
        'ITSMServiceLevelManagement',
        'ImportExport',
    ];

    # define the version of the included packages
    $Self->{PackageVersion} = '3.3.7';

    # define miminum required itsm version (if installed already)
    $Self->{MinimumITSMVersion} = '1.3.1';

    # delete some modules from %INC to prevent errors
    # when updating older ITSM packages
    delete $INC{'Kernel/System/GeneralCatalog.pm'};
    delete $INC{'Kernel/System/ITSMConfigItem.pm'};

    return $Self;
}

=item CodeInstall()

run the code install part

    my $Result = $CodeObject->CodeInstall();

=cut

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    # check requirements
    my $ResultOk = $Self->_CheckRequirements();

    if ($ResultOk) {

        # install the ITSM packages
        $ResultOk = $Self->_InstallITSMPackages();
    }

    else {

        # error handling
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Installation failed! See syslog for details.",
        );

        # uninstall this package
        $Self->_UninstallPackage(
            PackageList    => ['ITSM'],
            PackageVersion => $Self->{PackageVersion},
        );

        return;
    }

    return 1;
}

=item CodeUpgrade()

run the code upgrade part

    my $Result = $CodeObject->CodeUpgrade();

=cut

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    # check requirements
    my $ResultOk = $Self->_CheckRequirements();

    if ($ResultOk) {

        # install the ITSM packages
        $ResultOk = $Self->_InstallITSMPackages();
    }

    else {

        # error handling
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Installation failed! See syslog for details.",
        );

        # uninstall this package
        $Self->_UninstallPackage(
            PackageList    => ['ITSM'],
            PackageVersion => $Self->{PackageVersion},
        );

        return;
    }

    return 1;
}

=item CodeUninstall()

run the code uninstall part

    my $Result = $CodeObject->CodeUninstall();

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    # get the reverse package list
    my @ReversePackageList = reverse @{ $Self->{PackageNames} };

    # uninstall the packages
    $Self->_UninstallPackage(
        PackageList    => \@ReversePackageList,
        PackageVersion => $Self->{PackageVersion},
    );

    return 1;
}

=begin Internal:

=item _InstallITSMPackages()

installes the itsm packages

    my $Result = $CodeObject->_InstallITSMPackages();

=cut

sub _InstallITSMPackages {
    my ( $Self, %Param ) = @_;

    # install/upgrade the packages
    PACKAGE:
    for my $PackageName ( @{ $Self->{PackageNames} } ) {

        # create the file location
        my $FileLocation
            = $Self->{ConfigObject}->Get('Home') . $Self->{PackagePath} . $PackageName . '.opm';

        # read the content of the OPM file
        my $FileContent = $Self->{MainObject}->FileRead(
            Location        => $FileLocation,
            Mode            => 'binmode',
            Result          => 'SCALAR',
            DisableWarnings => 1,
        );

        next PACKAGE if !${$FileContent};

        # install/upgrade the package
        $Self->{PackageObject}->PackageInstall(
            String => ${$FileContent},
        );
    }

    return 1;
}

=item _CheckRequirements()

check requirements

    my $Result = $CodeObject->_CheckRequirements();

=cut

sub _CheckRequirements {
    my ( $Self, %Param ) = @_;

    # build a lookup hash of all ITSM package names
    my %ITSMPackage = map { $_ => 1 } @{ $Self->{PackageNames} };

    # get list of all installed packages
    my @RepositoryList = $Self->{PackageObject}->RepositoryList();

    PACKAGE:
    for my $Package (@RepositoryList) {

        # package is not an ITSM package
        next PACKAGE if !$ITSMPackage{ $Package->{Name}->{Content} };

        # check if the package version version is at least the minimum required itsm version
        my $CheckVersion = $Self->_CheckVersion(
            Version1 => $Self->{MinimumITSMVersion},
            Version2 => $Package->{Version}->{Content},
            Type     => 'Min',
        );

        # itsm modul version is higher than minimum version
        next PACKAGE if $CheckVersion;

        # error handling
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Package '$Package->{Name}->{Content}' "
                . "version $Package->{Version}->{Content} is installed. "
                . "You need to upgrade to at least version $Self->{MinimumITSMVersion} first!",
        );

        return;
    }

    # check files
    FILE:
    for my $File ( @{ $Self->{PackageNames} } ) {

        # create file location
        my $Location = $Self->{ConfigObject}->Get('Home') . $Self->{PackagePath} . $File . '.opm';

        if ( !-f $Location ) {

            # error handling
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Could not find file $File!",
            );

            return;
        }

        # read the content of the file
        my $FileContent = $Self->{MainObject}->FileRead(
            Location        => $Location,
            Mode            => 'binmode',
            Result          => 'SCALAR',
            DisableWarnings => 1,
        );

        # file is ok
        if ( $FileContent && ref $FileContent eq 'SCALAR' && ${$FileContent} ) {
            next FILE;
        }

        # error handling
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Could not read file $File correctly!",
        );

        return;
    }

    return 1;
}

=item _UninstallPackage()

uninstalls packages, but only if the packages match the given package version

    my $Success = $CodeObject->_UninstallPackage(
        PackageList    => [ 'ITSMCore', 'GeneralCatalog' ],
        PackageVersion => '2.0.2',
    );

=cut

sub _UninstallPackage {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Attribute (qw(PackageList PackageVersion)) {
        if ( !$Param{$Attribute} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $Attribute!",
            );
            return;
        }
    }

    # get list of packages to uninstall
    my @PackageList = @{ $Param{PackageList} };

    # get list of all installed packages
    my @RepositoryList = $Self->{PackageObject}->RepositoryList();

    for my $Package (@PackageList) {

        REPOSITORYPACKAGE:
        for my $RepositoryPackage (@RepositoryList) {

            next REPOSITORYPACKAGE if $RepositoryPackage->{Name}->{Content} ne $Package;
            next REPOSITORYPACKAGE
                if $RepositoryPackage->{Version}->{Content} ne $Param{PackageVersion};

            # get package content from repository
            my $PackageContent = $Self->{PackageObject}->RepositoryGet(
                Name    => $RepositoryPackage->{Name}->{Content},
                Version => $RepositoryPackage->{Version}->{Content},
            );

            # uninstall the package
            $Self->{PackageObject}->PackageUninstall(
                String => $PackageContent,
            );
        }
    }

    return 1;
}

=item _CheckVersion()

checks if Version2 is at least Version1

    my $Result = $CodeObject->_CheckVersion(
        Version1 => '1.3.1',
        Version2 => '1.2.4',
        Type     => 'Min',
    );

=cut

sub _CheckVersion {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Version1 Version2 Type)) {
        if ( !defined $Param{$_} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "$_ not defined!",
            );
            return;
        }
    }
    for my $Type (qw(Version1 Version2)) {
        my @Parts = split( /\./, $Param{$Type} );
        $Param{$Type} = 0;
        for ( 0 .. 4 ) {
            if ( defined $Parts[$_] ) {
                $Param{$Type} .= sprintf( "%04d", $Parts[$_] );
            }
            else {
                $Param{$Type} .= '0000';
            }
        }
        $Param{$Type} = int( $Param{$Type} );
    }
    if ( $Param{Type} eq 'Min' ) {
        return 1 if ( $Param{Version2} >= $Param{Version1} );
        return;
    }
    elsif ( $Param{Type} eq 'Max' ) {
        return 1 if ( $Param{Version2} < $Param{Version1} );
        return;
    }

    $Self->{LogObject}->Log(
        Priority => 'error',
        Message  => 'Invalid Type!',
    );
    return;
}

1;

=end Internal:

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
