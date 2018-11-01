#!/usr/bin/perl
require 'getopts.pl';
$|=1;
$pgm_nm =  $0;
$pgm_nm =~ s|.*/||;
# dirname $tm = ( split(" ", &TimeStamp() ) )[0]; $debug_file = "/tmp/$pgm_nm.debug.$tm";
  
&Getopts( 'dTr:' );
$opt_r = 60 if ! $opt_r;   # 60 sec refresh
$report_file_refresh = $opt_r;
# $opt_d = 1;    # UNCOMMENT THIS LINE TO FORCE DEBUGGING OPTION
  
if ( !@ARGV ) {
    print STDERR <<_EOF_;
    
      Outputs Autosys job report in csv format to stdout for ITRS toolkit.
      Utilizes Autosys autorep command.
      Returns immediately by returning the last autosys job report previously saved in a file 
      or just the ITRS header if there is no report.
      Always checks whether report file is stale and if so starts a background process to create one.
      Very old files (10x refresh period) are removed.
      The report file will be like /tmp/$pgm_nm.* 
        
    
usage:   $0 [ -T ] [ -r refresh_wait_sec ] wildcarded_autosys_job_name
            -T list only top-level jobs/boxes
            -r wait_sec_to_refresh_report_file     default: $r_opt sec
            -d activate debugging                  debug file: $debug_file
example: $0  XYZ%REPORT%
_EOF_
    exit 1
}
  
$job_prefix = $ARGV[ 0 ];
$report_now = "/tmp/$pgm_nm.$job_prefix";
$report_new =  $report_now . ".new";
$report_rdy =  $report_now . ".rdy";
# if the file is missing or old spawn a process to create a new one for next time (old or missing is the same thing)
$now = time;
$rep_now_age =  ( -f $report_now ) ?  $now - file_mtime( $report_now ) : 999999;
$rep_new_age =  ( -f $report_new ) ?  $now - file_mtime( $report_new ) : 999999;
$rep_rdy_age =  ( -f $report_new ) ?  $now - file_mtime( $report_rdy ) : 999999;
  
&pr_debug( "printing header" );
print "jobName,lastStart,lastEnd,status,runPri,exit\n"; 
    
&pr_debug( "age: now= $rep_now_age  new= $rep_new_age    refresh report_file_refresh= $report_file_refresh"  );
# get rid off old files if present
unlink $report_rdy if  $rep_rdy_age > 10 * $report_file_refresh;
unlink $report_new if  $rep_new_age > 10 * $report_file_refresh;
unlink $report_now if  $rep_now_age > 10 * $report_file_refresh;
  
if ( -f $report_rdy ) {     # new report file is ready
   if ( -f $report_new ) {
      &pr_debug( "accepting trigger   $report_rdy age=$rep_rdy_age  report_file_refresh=$report_file_refresh" );   
      rename $report_new, $report_now || exit_err ( "can not rename $report_new to $report_now" );
      $rep_now_age = $rep_new_age;
   }
   unlink $report_rdy || &exit_err( "can not remove $report_rdy" );  # too old
}
  
if ( ! -f $report_new && ( $rep_now_age > $report_file_refresh ) ) {
   &pr_debug( "GENERATING new report file" );
   system("ksh -c \"umask 111; autorep -J $job_prefix > $report_new 2>&1 && touch $report_rdy\" >/dev/null 2>&1 &" );
#  chmod 666, $report_now, $report_new;   # just in case 
   &pr_debug( "spawned generation of a new file; for now use what is available" );
}
&pr_debug( "opening $report_now     creaing jobstatus "); ########
if ( ! open ( "RD", "$report_now" ) ) {
   &pr_headline_var( "$pgm_nm", "report not ready - waiting" );
   &pr_debug( "failed to open $report_now" ) ;
   exit 0;
}
  
while (<RD>) {
   next if /^\s*$/;
        # if job name is the only thing on the line,  merge it with status on the next line 
   if ( /^(\s*\w+)\s*$/ ) {
#      print " =======$1======= \n";
      $save_job_name=$1;   # including indented space
      next;
   }
   if ( $save_job_name ) {
       s/^\s+/ /;
       $_ = $save_job_name . $_;
       undef $save_job_name;
   }
   if ( /^(\s*)(\w+)/ ) {
      ( $level, $job ) = ( length( $1 ),$2 );
#     print "++$1+++$2++   now: $level > last: $job_level{ $job } ? ";
      $job_level{ $job } = $level if $level > $job_level{ $job }; 
#     print " job level= $job_level{ $job }\n";
   }
   push( @jobstatus , $_ );
}
foreach $line ( @jobstatus ) {
   $line =~ /^(\s*)(\S+)/  ;
   ( $level, $job ) = ( length( $1 ),$2 );
     
   if ( $opt_T ) {
     &build_row ($line) if $job_level{$job} == 0;
   }
   else {
     &build_row ( $line ) if $level == $job_level{ $job };
   }
}
&pr_debug( "created jobstatus   printing out" );
$now = &TimeStamp();
$ftime =  &TimeStamp( &file_mtime( "$report_now" ) );
&pr_headline_var( 'created', $ftime );
&pr_headline_var( 'displayed', $now );
&pr_debug("created=$ftime displayed=$now" );
&pr_headline_var( 'ALL', $total{ALL}, 0 );
&pr_headline_var( 'FA', $total{FA}, 0 );
&pr_headline_var( 'TE', $total{TE}, 0 );
&pr_headline_var( 'ST', $total{ST}, 0 );
&pr_headline_var( 'RE', $total{RE}, 0 );
&pr_headline_var( 'SU', $total{SU}, 0 );
&pr_headline_var( 'RU', $total{RU}, 0 );
&pr_headline_var( 'OI', $total{OI}, 0 );
print join( '', @jobreport);
&pr_debug( "done   total= $total{ALL} " );
#--------------------------------------------------------------------------
sub build_row() {
   my $line = shift;
   chomp $line;
   return if $line =~ /____________|Job Name/;
     
   $line =~ s/-----/--- ---/g;  # split one missing date field into two
   ( $jName, $jStartDate, $jStartTime, $jEndDate, $jEndTime, $jobStatus, $jobRunPri, $jobExit) = split( " ", $line ) ; 
#  print "[", join("][", $jName, $jStartDate, $jStartTime, $jEndDate, $jEndTime, $jobStatus, $jobRunPri, $jobExit),"]\n";
#  print "$jStartDate $jStartTime  ==>   $jEndDate $jEndTime \n";
     
   $jStart = &fmt_date( $jStartDate, $jStartTime );
   $jEnd   = &fmt_date( $jEndDate,   $jEndTime );
     
   $line = sprintf join( ",", $jName, $jStart, $jEnd, $jobStatus, $jobRunPri, $jobExit ) . "\n";
   push( @jobreport, $line);
   $total{ ALL }++;
   $total{ $jobStatus }++;
}
  
#--------------------------------------------------------------------------
sub pr_headline_var {          # itrs summary header
   my( $head_name, $head_value, $dflt_value ) = @_;
     
   $head_value = $dflt_value if ! $head_value && defined $dflt_value;
     
   $head_value =~ s/,/ /g;     # commas not allowed; it is a delimiter
   print "<!>$head_name,$head_value\n";
}
  
#-------------------------------------------------------------
sub exit_err {
    my( $msg ) = @_;
    &pr_headline_var( $pgm_nm, "error: $msg" );
    &pr_debug( "with error: $msg" );
    exit 3;
}
  
#-------------------------------------------------------------
sub fmt_date() {
   my ($date, $time) = @_;
     
   return '' if $date =~ /---/;
     
   my ( $mm, $dd, $yyyy ) = split( /\//, $date );
     
   return ( "$yyyy-$mm-$dd $time" );
}
#-------------------------------------------------------------
sub file_sz {
   my( $fsize )= ( stat( $_[0] ) )[7] ;
   &pr_err( "stat of [@_]: $!") if ( ! defined( $fsize )  );
   return ( $fsize );
}
#-------------------------------------------------------------
sub file_mtime {
   my( $mtime )= (stat( $_[0] ))[9] ;
   &pr_err( "stat of [@_]: $!") if ( ! defined( $mtime )  );
   return ( $mtime);
}
  
#-------------------------------------------------------------
sub pr_debug {
   return if ! $opt_d;
     
   if ( ! $opened_debug_file ) {
      open ( "DEBUG", ">>$debug_file" ) || &pr_err( "unable to open $debug_file" );
      $opened_debug_file = 1;
      chmod 0666, $debug_file;
   }
   print DEBUG &_pr_fmt( " DEBUG: $$ $job_prefix @_\n" );
}
  
#-------------------------------------------------------------
sub TimeStamp {
   my $in_time = shift;
   $in_time = time if ( ! $in_time ); #use current time if no arg passed
   my ( $sec, $min, $hr, $day, $mo, $yr ) = localtime( $in_time );
#  YYYY-MM-DD  : ISO 8601 date format
   sprintf( "%04d-%02d-%02d %02d:%02d:%02d", 1900 + $yr, ++$mo, $day, $hr, $min, $sec ); }
#-------------------------------------------------------------
sub _pr_fmt {
  return( &TimeStamp() .  " @_" );
}
#-------------------------------------------------------------
sub pr_out {
  print STDOUT &_pr_fmt( " @_\n" );
}
#-------------------------------------------------------------
sub pr_err {
  print STDERR &_pr_fmt( " ERROR: @_\n" );
}