package VZ::Stalker;

use Sys::Statistics::Linux;
#use Data::Dumper;

# -------------------------------- defaults ------------------------------- #
our $vzlist     = '/usr/sbin/vzlist';
our $ps         = '/bin/ps';

# -------------------------------- methods -------------------------------- #
sub new
{
    # sub to act as a reference for
    # calling other methods in the package
    my $class           = shift;
    my %args            = @_;
    my $self            = {};
    $self->{vzlist}     = $args{vzlist} || $vzlist;
    $self->{ps}         = $args{ps} || $ps;
    bless( $self, $class );
    return $self;
}

###
sub get_load
{
    # make the call as lightweight as possible by strictly setting
    # the value to 0 as suggested by Devel::NYTProf ( http://bit.ly/bUq8Kz )
    my $lxs = Sys::Statistics::Linux->new(
        loadavg             => 1,
        memstats            => 1,
        sysinfo             => 0,
        cpustats            => 0,
        procstats           => 0,
        netstats            => 0,
        sockstats           => 0,
        processes           => 0,
    );
    sleep 1; my $stat   = $lxs->get;

    my $Stat = {};

    $Stat->{load1}    = $stat->loadavg->{avg_1};
    $Stat->{load5}    = $stat->loadavg->{avg_5};
    $Stat->{ram_free} = int($stat->memstats->{memfree}/1024);

    return $Stat;
}
###

###
sub get_sys_stats
{
    local $lxs = Sys::Statistics::Linux->new(
        loadavg             => 1,
        memstats            => 1,
        cpustats            => 1,
        procstats           => 1,
        sysinfo             => 0,
        netstats            => 0,
        sockstats           => 0,
        processes           => 0,
        pgswstats           => 0,
    );
    sleep 1; local $stat = $lxs->get;

    local $Stat = {}; local $cpu  = $stat->cpustats->{cpu};
    $stat->memstats->{memused}     = int($stat->memstats->{memused}/1024);
    $stat->memstats->{memfree}     = int($stat->memstats->{memfree}/1024);
    $stat->memstats->{memtotal}    = int($stat->memstats->{memtotal}/1024);
    $stat->memstats->{swapused}    = int($stat->memstats->{swapused}/1024);
    $stat->memstats->{swapfree}    = int($stat->memstats->{swapfree}/1024);


    ## LOAD-AVERAGE CPU-SYSTEM CPU-IOWAIT CPU-USER CPU-NICE CPU-IDLE RUN-PROC I/O-PROC RAM-TOTAL RAM-USED RAM-FREE
    local $topHead     = " %-18s %-5s %-5s %-5s %-5s %-6s %-4s %-4s %-9s %-9s %-9s %-9s %-9s\n %-s\n";
    local $topTail     = " %-18s %-5d %-5d %-5d %-5d %-6d %-4d %-4d %-9d %-9d %-9d %-9d %-9d\n";
    local $delimiter   = q[-] x 115;

    $Stat->{host_table} = sprintf($topHead,"LOAD AVERAGE","%SYS",
        "%IO","%USR","%NICE","%IDLE","RUN","I/O","RAM-TOTAL","RAM-USED","RAM-FREE","SWAP-USED","SWAP-FREE",$delimiter);
    $Stat->{host_table} .= sprintf($topTail, $stat->loadavg->{avg_1}."/".$stat->loadavg->{avg_5}."/".$stat->loadavg->{avg_15},
        $cpu->{system},$cpu->{iowait},$cpu->{user},$cpu->{nice},$cpu->{idle},$stat->procstats->{running},$stat->procstats->{blocked},
        $stat->memstats->{memtotal},$stat->memstats->{memused},$stat->memstats->{memfree},$stat->memstats->{swapused},$stat->memstats->{swapfree});

    $Stat->{load1}    = $stat->loadavg->{avg_1};

    return $Stat;
}
###

###
sub get_vzlist
{
    ## 1st param as construct to $self
    ## to access parent namespace
    local $self        = shift;
    local %args        = @_;
    local $vzlist      = $args{vzlist} || $self->{vzlist} || $vzlist;
    my $Stat = {};

    local $vzlistRaw = `$vzlist -H -o veid,laverage,hostname -s laverage|tail -10`;
    $vzlistRaw =~ s/^\r+|\n|^\s+//g; $vzlistRaw =~ s/\s\s\s+/\n/g;

    $Stat->{vzlist_table} = "=> top 10 VM's sorted by load:\n\n$vzlistRaw\n\n";

    return $Stat;
}
###

###
sub get_pid_stats
{
    ## 1st param as construct to $self
    ## to access parent namespace
    my $self        = shift;
    my %args        = @_;
    my $ps          = $args{ps} || $self->{ps} || $ps;
    my $Stat = {};

    local $ps_out = `$ps -eo pid,%cpu --sort:pcpu|tail -20`;
    local @pidsRaw = split(/\s+/, $ps_out);
    shift(@pidsRaw) if( $pidsRaw[0] eq '' ); # remove blanks

    # pid is key, %cpu is value
    local %PidsCpu = (); %PidsCpu = @pidsRaw;

    # config in a hash for simple exists() checks
    my %config = (
        'io' => {
                'read'          => '',
                'write'         => '',
                'dirty'         => '',
                'fsyncs_total'  => '',
            },
        'proc' =>   {
                'Name:'         => '',
                'envID:'        => '',
                'Threads:'      => '',
                'State:'        => '',
            },
    );
    my $tStat = {}; my @black_pids = ();
    # -------------------------------- config -------------------------------- #
    #### TOP HEADER FOR PROC TABLE ###
    ## PID VMID NAME CPU% STATE THREADS DIRTY(mb) FSYNC_TOTAL READ(mb) WRITE(mb) PATH
    local $btmHead = " %-8s %-6s %-20s %-6s %-6s %-8s %-10s %-10s %-10s %-10s %s\n %-s\n";
    local $btmTail = " %-8d %-6d %-20s %-6.2f %-6s %-8s %-10d %-11d %-10d %-10d %s\n";
    local $delimiter = q[-] x 115;

    $Stat->{proc_table} = sprintf($btmHead,"PID","VMID","NAME","CPU%", "STATE","THREADS",
                    "DIRTY(mb)","FSYNC_TOTAL","READ(mb)","WRITE(mb)","PATH",$delimiter);

    # -------------------------------- foreach /proc -------------------------------- #
    ## parse some /proc baby
    foreach (sort { $PidsCpu{$a} <=> $PidsCpu{$b} } keys %PidsCpu)
    {
       next if int($_) == 0 || $_ == $$; # skip finished/self pids

        ## parse PID data
        if (open(PIDSTAT, "</proc/$_/status"))
        {
            while (my $line = <PIDSTAT>)
            {
                chomp($line); my ($key,$value) = split(/\s+/, $line);

                if(exists $config{'proc'}{$key})
                {

                    $tStat->{data}->{$_}->{'%CPU:'} = $PidsCpu{$_};
                    $tStat->{data}->{$_}->{$key}    = $value;

                    next if (defined $tStat->{data}->{$_}->{'Path:'});
                    if(-e "/proc/$_/exe" && -l "/proc/$_/exe") { $tStat->{data}->{$_}->{'Path:'} = readlink "/proc/$_/exe" }
                    else { $tStat->{data}->{$_}->{'Path:'} = 'N/A' }
                }
                else { next; }
            }
            close(PIDSTAT);
        }
        # we dont want to break here if the status file
        # is not present in the meantime. (maybe PID finished?)
        else { next; }
        ## end parse PID data

        ## get defined i/o stuff if possible
        if(exists $tStat->{data}->{$_}->{'envID:'})
        {
            local $/; ## slurp the file handle without a loop
            if(open(VMIO, "</proc/bc/".$tStat->{data}->{$_}->{'envID:'}."/ioacct"))
            {
                local $ioacct = <VMIO>;
                close(VMIO);
                local @ioCols = split( /\s+/, $ioacct );
                shift(@ioCols); #remove blanks
                local %tmpHASH = @ioCols;
                foreach my $key ( keys %tmpHASH )
                {
                    if( exists $config{'io'}{$key} )
                    {
                        $tmpHASH{$key} = int(($tmpHASH{$key} / 1024) / 1024) unless $key eq 'fsyncs_total';
                        $tStat->{data}->{$_}->{$key} = $tmpHASH{$key};
                    }
                    else { next; }
                }
            } ## end open ioacct

            ## TODO: do some load checks here before loading any additional data
            push @black_pids, $tStat->{data}->{$_}->{'envID:'} unless int($tStat->{data}->{$_}->{'envID:'}) == 0;
        }
        ## end io stuff

        ## print the table line
        ### PID VMID NAME CPU% STATE THREADS DIRTY(mb) FSYNC_TOTAL READ(mb) WRITE(mb) PATH
        # " %-8d %-6d %-20s %-5.2f %-6s %-8s %-10d %-11d %-10d %-10d %s\n";
        $Stat->{proc_table} .= sprintf($btmTail, $_,$tStat->{data}->{$_}->{'envID:'},$tStat->{data}->{$_}->{'Name:'},
            $tStat->{data}->{$_}->{'%CPU:'},$tStat->{data}->{$_}->{'State:'},$tStat->{data}->{$_}->{'Threads:'},
            $tStat->{data}->{$_}->{'dirty'},$tStat->{data}->{$_}->{'fsyncs_total'},$tStat->{data}->{$_}->{'read'},
            $tStat->{data}->{$_}->{'write'},$tStat->{data}->{$_}->{'Path:'});

    }
    # -------------------------------- end foreach /proc -------------------------------- #

    $Stat->{proc_table} .= "\n\n=> VMID's sorted by appearness (based on the snapshot above):\n\n";

    my %blackPIDS = (); $blackPIDS{$_}++ for @black_pids;
    foreach( sort { ($blackPIDS{$a} <=> $blackPIDS{$b}) || ($a <=> $b) } keys %blackPIDS )
    {
        $Stat->{proc_table} .= sprintf("%-4s: %3s\n", $_, $blackPIDS{$_});
    }

    return $Stat;
}
###

1; ## end package / return true
