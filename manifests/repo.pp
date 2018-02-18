#
# This class initializes a backup run
# 
# use borgbackup::archive define to add archives to
# this repo
#
# Parameters:
#   $reponame
#     the name of the repo 
#     Defaults to $title
#   $target
#     the target where to put the backup (env BROG_REPO)
#   $passphrase
#     the passphrase to use for the repo
#     if empty (the default, random pasphrase is generated
#     and saved gpg encrypted in a git repo. see
#     borgbackup::git for more information.
#   $passcommand
#     a command to get the password of the repo
#     defaults to 'default' which creates a 
#     passcommand to extract the key from the gitrepo.
#   $env_vars
#     additional environment variables to set 
#     before the execution of borg.
#     defaults to {}
#     for remote repositories, set this to:
#     { BORG_RSH: 'ssh -i /etc/borgbackup/.ssh/YOUR_KEY' }
#   $encryption
#     the encryption for the backup.
#     defaults to 'keyfile'
#   $append_only
#     if true, an append_only repo is created (no purge)
#     defaults to false
#   $storage_quota
#     storage quota to set defaults to ''
#   $archives
#     Hash of archives to create for this repo
#     See ::borgbackup::archive for options
#     $reponame is added as default.
#   $icinga_old
#     you can run a rudimentary icinga/nagios check
#     to see if a repo is old. this parameter
#     after how many seconds a repo is considered old
#     defaults to 90000 (25h)
#   $crontab_define
#     resource used to create a crontab entry
#     defaults to 'cron'
#     set this to a resource to create systemd timers
#     if you prefer systemd timers
#     if set to '' no cron job will be generated
#   $crontabs
#     parameters for $crontab_define
#     defaults to {}
#     which if crontab_define is 'cron' (the default)
#     creates a nightly cronjob for doing backup with:
#     cron { "borgbackup run ${reponame}":
#       command => "${configdir}/repo_${reponame}.sh run",
#       user    => 'root',
#       hour    => fqdn_rand(3,'borgbackup'),
#       minute  => fqdn_rand(60,'borgbackup'),
#     }
#
define borgbackup::repo (
  $reponame       = $title,
  $target         = '',
  $passphrase     = '',
  $passcommand    = 'default',
  $env_vars       = {},
  $archives       = {},
  $encryption     = 'keyfile',
  $append_only    = false,
  $storage_quota  = '',
  $icinga_old     = 90000,  # 25 hours 
  $crontab_define = 'cron',
  $crontabs       = {},
){

  include ::borgbackup

  $configdir = $::borgbackup::configdir

  if $passcommand == 'default' {
    include ::borgbackup::git

    $_passcommand = "export GNUPGHOME='${::borgbackup::git::gpg_home}'; gpg --decrypt ${::borgbackup::git::git_home}/${::fqdn}/${reponame}_pass.gpg"
    if $passphrase == '' {
      # default behaviour, save a random passphrase encrypted in git repo 
      $_passphrase = ''
      $_passphrase_to_git = 'random'
    } else {
      # save a configured passphrase encrypted in git repo
      $_passphrase = ''
      $_passphrase_to_git = $passphrase
    }
    # so add to git repo ...
    $add_gitrepo = {
      "gitrepo-add-${::fqdn}-${reponame}" => {
        passphrase => $_passphrase_to_git,
        reponame   => $reponame,
      },
    }
    create_resources('::borgbackup::addtogit', $add_gitrepo)
  } else {
    if ( $passphrase == '' and $passcommand == '' ) {
      fail('borgbackup::repo you cannot use an empty passphrase without passcommand')
    } else {
      # you have either set a passphrase or a passcommand (or both) on your own, do not use git.
      $_passphrase = $passphrase
      $_passcommand = $passcommand
    }
  }


  exec{"initialize borg repo ${reponame}":
    command => "${configdir}/repo_${reponame}.sh init",
    unless  => "${configdir}/repo_${reponame}.sh check",
    require => Concat["${configdir}/repo_${reponame}.sh"],
  }

  # create the repo script
  #
  concat { "${configdir}/repo_${reponame}.sh":
    owner => 'root',
    group => 'root',
    mode  => '0700',
  }

  concat::fragment{ "borgbackup::repo ${reponame} header":
    target  => "${configdir}/repo_${reponame}.sh",
    content => template('borgbackup/repo_header.erb'),
    order   => '00-header',
  }

  concat::fragment{ "borgbackup::repo ${name} footer":
    target  => "${configdir}/repo_${reponame}.sh",
    content => template('borgbackup/repo_footer.erb'),
    order   => '99-footer',
  }

  $archdefaults = {
    reponame => $reponame,
  }

  create_resources('::borgbackup::archive', $archives, $archdefaults)

  if $crontab_define != '' {
    if $crontabs == {} and $crontab_define == 'cron' {
      $_crontabs = {
        "borgbackup run ${reponame}" => {
          'command' => "${configdir}/repo_${reponame}.sh run",
          'user'    => 'root',
          'hour'    => fqdn_rand(3,'borgbackup'),
          'minute'  => fqdn_rand(60,'borgbackup'),
        },
      }
    } else {
      $_crontabs = $crontabs
    }
    create_resources( $crontab_define, $_crontabs )
  }
}