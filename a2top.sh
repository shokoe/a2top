#!/bin/bash
version="a2top version 0.1 - by Guy 'Shoko' Egozy and Ilya 'Yalda' Sher"

## Defaults
# url for status page
status_url='http://127.0.0.1/server-status'
# screen update interval - hotkey s
delay=2
# scoreboard display mode, 0-3 - hotkey c
sb_dis=2
# info disaply mode, 0-1 - hotkey o 
info_dis=0
# uptime disaply mode, 0-2 - hotkey u
uptime_dis=1
# display inactive queries
ina_dis=0
# table regex grep value
regex_string=""; vregex=0
# sort column
col_sort=""
# sort column reverse
col_sort_rev=0
# highlight regex
hlight=""

help_screen='a2top - Version 0.1b

Hotkeys:
  p|P    Pause refresh
  d	 Tcpdump on all sockets by pid
  	 * Experimentale
  s|S    Change refresh interval
  c|C    Cycle through scoreboard disply modes
  A      Prompts for {cmd} and execute
         "/etc/init.d/apache2 {cmd}"
  o|O    Toggle info display
  t      Sort by column
         Gets only full column names
         Knows which columns are numeric
         Sort is reversed for numeric columns
  T      Cancel column sort
  y	 Reverse column sort
  r      Regex grep on query table, uses egrep,
         regex is in double quotes
  v      Regex exclude grep on query table, usess
         egrep -v, regex is in double quotes
  R      Cancel regex grep on query table
  g	 Highlight regex (sed address)
  	 Does not work with the grep options
  i      Filter inactive queries (state waiting
         and open - _ and .)
  l	 Strace - strcae to file and "less +F" on it
  	 To activate scroll - ^C
	 To resume tail - F
	 To exit back to a2top - ^C and q
	 * Does not work with MPM worke (no thread id)
  k|K    Kill process (use with care)
  W      Save configuration (default ~/.a2toprc)
  h|H|?  Show this help
  q|Q    Quit

Command line options:
  -h	show help
  -v	show version
  -u	apache server-status url, detault: "http://127.0.0.1/server-status"
  -c	configuration file, default: "~/.a2toprc"
  -t	temp directory, default: "/dev/shm/a2top/{pid}"
  -l	strace options, default: "-t -e trace=network"

Scoreboard Key:
  "_" Waiting for Connection, "S" Starting up, "R" Reading Request,
  "W" Sending Reply, "K" Keepalive (read), "D" DNS Lookup,
  "C" Closing connection, "L" Logging, "G" Gracefully finishing,
  "I" Idle cleanup of worker, "." Open slot with no current process

Request table legend:
  Srv    Child Server number - generation
  PID    OS process ID
  Acc    Number of accesses this connection / this child / this slot
  M      Mode of operation
  CPU    CPU usage, number of seconds
  SS     Seconds since beginning of most recent request
  Req    Milliseconds required to process most recent request
  Conn   Kilobytes transferred this connection
  Child  Megabytes transferred this child
  Slot   Total megabytes transferred this slot

TODO:
   * check that bc/lsof is installed
   * add info on proc (pid=22426; lsof -p $pid | sed -n "1p; /TCP/p;"; ls -la /proc/$pid/fd/;)
   * add Esc on input (maybe ^C too)
   * make server-status requests on a single connection

hit q to continue'

cmd_help="Usage: $0 [-hv] [-u status_url] [-c conifguration_file] [-t tmp_dir] [-l strace_options]
  -h	show help
  -v	show version
  -u	apache server-status url, detault: http://127.0.0.1/server-status
  -c	configuration file, default: ~/.a2toprc
  -t	temp directory, default: /dev/shm/a2top/{pid}
  -l	strace options, default: -t -e trace=network
Use ?|h while running to get online help"

txtund=$(tput sgr 0 1)	# Underline
txtbld=$(tput bold)	# Bold
txtblk=$(tput setaf 0)	# Black
txtred=$(tput setaf 1)	# Red
txtgrn=$(tput setaf 2)	# Green
txtylw=$(tput setaf 3)	# Yellow
txtblu=$(tput setaf 4)	# Blue
txtpur=$(tput setaf 5)	# Purple
txtcyn=$(tput setaf 6)	# Cyan
txtwht=$(tput setaf 7)	# White
txtrst=$(tput sgr0)	# Text reset
txtbred=$(tput setab 1)	# Red
txtbgrn=$(tput setab 2)	# Green
txtbylw=$(tput setab 3)	# Yellow
txtbblu=$(tput setab 4)	# Blue
txtbpur=$(tput setab 5)	# Purple
txtbcyn=$(tput setab 6)	# Cyan
txtbwht=$(tput setab 7)	# White
txtspace='                                                                                                                        '

clrr="$txtrst"			# reset
clru2="$txtbld$txtcyn"		# uptime main 
clru1="$txtcyn"			# uptmime secondary 
clrt2="$txtbld$txtgrn"		# status top main 
clrt1="$txtgrn"			# status secondary 
clri2="$txtpur$txtbld"		# info main 
clri1="$txtpur"			# info secondary 
clrs1="$txtylw"			# scoreboard count main 
clrs2="$txtbld$txtylw"		# scoreboard count secondary 
clrh1="$txtbylw$txtblk" 	# table head main 
clrh2="$txtund$txtbylw$txtblk"	# table sorted column 
clrtb="$txtbld"			# table content 
clrhl="$txtbld$txtylw"
clre="$txtbred$txtbld"		# error

sb_display_none(){
	rm $tmp/sb
	out_sb_cnt=""
	out_sb_cnt_size=0
}

sb_display_full(){
	out_sb="`echo \"$out\" | \egrep '^[_SRWKDCLGI.]{10,}$'`"
	out_sb_cnt="$out_sb\n"
	out_sb_cnt_size=`echo "$out_sb_cnt" | wc -l`
	echo -ne "$txtbld$txtred$out_sb_cnt$txtrst" | sed "s#^# #" > $tmp/sb
}

sb_display_short(){
	out_sb="`echo \"$out\" | egrep '^[_SRWKDCLGI.]{10,}$'`"
	out_sb_cnt_pre="`echo \"$out_sb\" | sed 's# ##g; s#\(.\)#\1\n#g;' | sed '/^$/d' |\
		awk '
			BEGIN{
				a["_"]=a["S"]=a["R"]=a["W"]=a["K"]=a["D"]=0
				a["C"]=a["L"]=a["G"]=a["I"]=a["."]=0
				b["_"] = "Waiting"; b["S"] = "Starting"; b["R"] = "Reading"
				b["W"] = "Sending"; b["K"] = "Keepalive"; b["D"] = "DNS"
				b["C"] = "Closing"; b["L"] = "Logging"; b["G"] = "Graceful";
				b["I"] = "Idle"; b["."] = "Open";
			}
			function count(x){
				a[x]++;
			}
			count($1)
			END{
				for ( item in a ) 
					print item":"a[item]
		}' | xargs `"
	out_sb_cnt="`printf \"%-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s\\\n\" $out_sb_cnt_pre`\n"
	out_sb_cnt_size=`echo "$out_sb_cnt" | wc -l`
	echo -ne "$clrs1$out_sb_cnt$clrr" | sed "s#:\([0-9][0-9]*\)#:$clrr$clrs2\1$clrr$clrs1#g; s#^# #" > $tmp/sb
}

sb_display_named(){
	out_sb="`echo \"$out\" | egrep '^[_SRWKDCLGI.]{10,}$'`"
	out_sb_cnt_pre="`echo \"$out_sb\" | sed 's# ##g; s#\(.\)#\1\n#g;' | sed '/^$/d' |\
		awk '
			BEGIN{
				a["_"]=a["S"]=a["R"]=a["W"]=a["K"]=a["D"]=0
				a["C"]=a["L"]=a["G"]=a["I"]=a["."]=0
				b["_"] = "Waiting"; b["S"] = "Starting"; b["R"] = "Reading"
				b["W"] = "Sending"; b["K"] = "Keepalive"; b["D"] = "DNS"
				b["C"] = "Closing"; b["L"] = "Logging"; b["G"] = "Graceful";
				b["I"] = "Idle"; b["."] = "Open";
			}
			function count(x){
				a[x]++;
			}
			count($1)
			END{
				for ( item in a ) 
					print b[item]" "a[item]
		}' | xargs `"
	out_sb_cnt="`printf \"%-9s %+3s %-9s %+3s %-9s %+3s %-9s %+3s %-9s %+3s %-9s %+3s\\\n\" $out_sb_cnt_pre`\n"
	echo -ne "$clrs1$out_sb_cnt$clrr" | sed "s# \([0-9][0-9]*\)# $clrr$clrs2\1$clrr$clrs1#g; s#^# #" > $tmp/sb
}

sb_display(){
	case $sb_dis in
		0) sb_display_none;;
		1) sb_display_short;;
		2) sb_display_named;;
		3) sb_display_full;;
	esac
}

tbl_display(){
	# get it
	out_head="`echo \"$out\" | egrep 'Srv.*PID' | sed 's#^ *##'`              "
	out_tbl="`echo \"$out\" | egrep '^  *[0-9][0-9]*-[0-9][0-9]* ' |\
		sed 's#^ *##' |\
		grep -v '/server-status'`"
	# cut it
	out_tbl="`echo \"$out_tbl\" | egrep \`(($vregex)) && echo '-v '\` \"$regex_string\" |\
		egrep \`(($vregex_ina)) && echo '-v '\` \"$regex_string_ina\" | head -$(($rows-$head_size-1))`"
	# get format
	out_tbl_format="`echo -en \"$out_head\n$out_tbl\" | awk '
		BEGIN{ for (i = 1; i <= 12; i++){
				max[i]=0
			}
		}
		{ 	for (i=1; i<=NF; i++){
				if ( length($i) > max[i] )
					max[i] = length($i)
			}
		}
		END{	for (i = 1; i <= 12; i++){
				printf "%s", "%-"max[i]"s  "
			}
			printf "%s", "%s"
		}'`"
	# format it
	out_head="`printf \"$out_tbl_format\\\n\" $out_head`"
	#out_tbl="`printf \"$out_tbl_format %s %s\\\n\" $out_tbl`"
	out_tbl="`echo \"$out_tbl\" | awk -v FORMAT=\"$out_tbl_format\\\n\" '{printf FORMAT, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13" "$14" "$15}'`"
	# sort it
	if [ "x$col_sort" != "x" ]; then
		col_sort_num="`echo \"$out_head\" | sed 's#  *#\n#g' | cat -n | egrep "\<$col_sort\>" |\
			awk '{print $1}'`"
		case $col_sort in
			M|VHost|Request)	case $col_sort_rev in
							0) sort_opt="-k $col_sort_num";;
							1) sort_opt="-r -k $col_sort_num";;
						esac;;
			*)			case $col_sort_rev in
							0) sort_opt="-r -n -k $col_sort_num";;
							1) sort_opt="-n -k $col_sort_num";;
						esac;;
		esac
		out_tbl="`echo \"$out_tbl\" | sort $sort_opt`"
		out_head="`echo \"$out_head\" |\
			sed \"s#$col_sort#$clrh2$col_sort$clrr$clrh1#\"`"
	fi
	# color it
	echo -e " $clrr$clrh1$out_head$txtspace$clrr" > $tmp/tbl
	# grep it
	if [ "x$regex_string" = "x" ]; then
		[ "x$hlight" != "x" ] &&\
			echo -e "$clrtb$out_tbl$clrr" | sed "s#^# #; /$hlight/s#^ \(.*\)\$# $clrr$clrhl\1$clrr$clrtb#;" >> $tmp/tbl ||\
			echo -e "$clrtb$out_tbl$clrr" | sed "s#^# #;" >> $tmp/tbl
	else
		echo -ne "$out_tbl" | GREP_COLORS="sl=01;37:ms=33" egrep --color=always `(($vregex)) && echo '-v '` "$regex_string" | sed "s#^# #;" >> $tmp/tbl
	fi
	#mv $tmp/tbl.tmp $tmp/tbl
	# add empty lines
	s=`cat $tmp/tbl | wc -l`
	for ((i=$rows; i>$(($head_size+$s)); i--)); do
		echo " " >> $tmp/tbl
	done
}

uptime_display(){
	case $uptime_dis in
		0)	rm $tmp/uptime; out_uptime="";;
		2)	out_uptime="`top -n 1 -b | head -5 | sed -n \"s#\\\$#$txtspace #; 1p; 3p; 4p; 5p;\"`"
			echo -e "$clru1$out_uptime$clrr" | sed "s#\([0-9.][0-9.]*[k%]\)#$clrr$clru2\1$clrr$clru1#g; s#^# #" > $tmp/uptime;;
		1|*)	out_uptime="Uptime: `uptime`"
			echo -e "$clru1$out_uptime$clrr" | sed "s#^# #" > $tmp/uptime;;
	esac
}

info_display(){
	case $info_dis in
		1)	[ "x$regex_string" != "x" ] && regex_info="\"$regex_string\"" || regex_info=""
			out_info="\"Refresh interval: $delay \" \
\"Scoreboard mode: $sb_dis\" \
\"Uptime mode: $uptime_dis\" \
\"Sort options: ${sort_opt:-none}\" \
\"Last kill pid: ${kill_pid:-none}\" \
\"Last kill signal: ${kill_sig:-none}\" \
\"Screen size: $rows:$cols\" \
\"Regex grep: `(($vregex)) && echo '-v '`${regex_info:-none}\" \
\"Hide inactive: $ina_dis\" \
\"Last apache: ${a2_init_cmd:-none}\" \
\"Parent PID: $$\" \
\"Real delay: $d\""
			printf "%-25s %-25s %-25s %s\n" \
				"@@Refresh interval: $delay" \
				"@@Scoreboard mode: $sb_dis" \
				"@@Uptime mode: $uptime_dis" \
				"@@Sort options: ${sort_opt:-none}" \
				"@@Last kill pid: ${kill_pid:-none}" \
				"@@Last kill signal: ${kill_sig:-none}" \
				"@@Screen size: $rows:$cols" \
				"@@Regex grep: `(($vregex)) && echo '-v '`${regex_info:-none}" \
				"@@Hide inactive: $ina_dis" \
				"@@Last apache: ${a2_init_cmd:-none}" \
				"@@Parent PID: $$" \
				"@@Highlight Regex: ${hlight:-none}" \
				"@@Real delay: $d" |\
				sed "s#\(\@@[^:]*:\)#$clrr$clri1\1$clrr$clri2#g; s#^# #; s#@@##g" > $tmp/info;;
				#sed "s#\([a-zA-Z ]*:\)#$clrr$clri1\1$clrr$clri2#g; s#^# #" > $tmp/info;;
		0|*)	out_info=""; rm $tmp/info;;
	esac
}

display_top(){
	out_top="`echo \"$out\" | sed -n '/Current Time/,/being processed/p' |\
		sed 's#^ *##;'`"
	# add spaces for aligned line wrap
	am=0
	for i in `seq \`echo "$out_top" | wc -l\``; do
		a[$i]=`echo "$out_top" | sed -n "${i}p" | wc -c`
		echo -n $i | egrep "^1$|^3$|^5$" >/dev/null && [ ${a[$i]} -gt $am ] && am=${a[$i]}
	done
	for j in 1 3 5; do
		sp=""
		for k in `seq $(($am-${a[$j]}+1))`; do
			sp="$sp "
		done
		out_top="`echo \"$out_top\" | sed \"$j{s#\\\$#$sp#}\"`"
	done

	# color and line-wrap it
	echo -e "$clrt1$out_top$clrr" |\
		sed "s#^# #; 1,6{s#: \(.*\)#: $clrr$clrt2\1$clrr$clrt1#g;}; 7,8{s#\([0-9][0-9.]*\)#$clrr$clrt2\1$clrr$clrt1#g;};" |\
		sed "1{N; s#\n##;}; 3{N; s#\n##;}; 5{N; s#\n##;}" > $tmp/top
}

save_conf(){
	echo "# Configuration for a2top
status_url='$status_url'
delay=$delay
sb_dis=$sb_dis
info_dis=$info_dis
uptime_dis=$uptime_dis
ina_dis=$ina_dis
regex_string_ina='$regex_string_ina'; vregex_ina=$vregex_ina
regex_string='$regex_string'; vregex=$vregex
col_sort='$col_sort'
col_sort_rev=$col_sort_rev
trace_opts='$trace_opts'
hlight='$hlight'" > $conf_file
}

exception_exit(){
	terminate noexit
	echo "
ERROR:
   Incorrect output from status page, check the following:
    * Apache is active
    * Status page is available at '$status_url' (use -u to change the default)
    * Lynx is installed
    * Apache mod_status is cofigured with 'ExtendedStatus On'
    * Finally check from command line that this works: 'lynx -dump -width=400 \"$status_url\"'"
	exit 2
}

term_dis(){
	kill -9 $dis_jobs
	echo -e "$txtrst"
}

display_prep(){
	out="`lynx -dump -width=400 \"$status_url\"`"
	echo "$out" | grep 'CPU Usage' &>/dev/null || exception_exit
	uptime_display & dis_jobs="$dis_jobs $!"
	display_top & dis_jobs="$dis_jobs $!"
	sb_display & dis_jobs="$dis_jobs $!"
	info_display & dis_jobs="$dis_jobs $!"
	wait $dis_jobs; dis_jobs=""
	head_size=`wc -l $tmp/uptime $tmp/top $tmp/info $tmp/sb 2>/dev/null | tail -1 | awk '{print $1}'`
	tbl_display & dis_jobs="$dis_jobs $!"
	wait $dis_jobs; dis_jobs=""
}

display(){
	trap term_dis INT TERM EXIT
	i=0
	while true; do 
		s=`date +%s.%N`
		dis_pre="`(($uptime_dis)) && cat $tmp/uptime
		cat $tmp/top
		(($info_dis)) && cat $tmp/info
		(($sb_dis)) && cat $tmp/sb | sed \"\\\$d\" | sed \"\\\${s#\\\$# \$clrr($((\`cat $tmp/tbl | egrep -v '^ *$|Srv  PID' | wc -l\`-1)) rows) #}\"
		echo
		cat $tmp/tbl`"
		#dis="`echo \"$dis_pre\" | sed \"s#\\\$# #; s#^#$(tput el)#;\"`"
		dis="`echo \"$dis_pre\" | sed \"s#\\\$#$(tput el) #;\"`"
		#echo -ne "\E[?25l\E[H\E[2J$dis"
		tput civis
		echo -ne "$((($i)) || tput clear)$(tput home)$dis$(tput cup $head_size 1)"
		tput cnorm
		i=$((++i))
		#tput cup $head_size 1
		#echo -n "- ${sort_opt} -"
		#echo -n "(rows:$((`cat $tmp/tbl | egrep -v '^ $' | wc -l`-1))) "
		if [ $(($head_size+2)) -gt $rows ]; then
			echo -n "${clre}Screen size too small$clrr"
		fi
		dis_jobs=""
		display_prep
		d=`echo "scale=3; ($delay-0.05+$s-\`date +%s.%N\`)/1" | bc`
		sleep `echo "$delay-0.05+$s-\`date +%s.%N\`" | bc`
	done
}

recycle(){
	exec 3>&2; exec 2> /dev/null
	tput rmam
	#tput mgc
	[ ! -z $main_pid ] && kill -9 $main_pid
	read rows cols <<< "`stty size`"
	rows=$(($rows-1))
	display_prep
	display &
	dis_pid=$!
	exec 2>&3; exec 3>&-
}

terminate(){
	exec 3>&2; exec 2> /dev/null
	kill -9 $dis_pid
	tput cup $rows 0
	echo -e "$txtrst"
	tput smam
	stty sane
	rm -rf $tmp
	exec 2>&3; exec 3>&-
	#tput cnorm
	tput rmcup
	[ "$1" = "noexit" ] && return
	exit
}

resize_window(){
	tput home
	kill -9 $dis_pid
	recycle
}

# Main :) - "The weekend starts here ..."

# defaults for command line options
conf_file=~/.a2toprc
tmp="/dev/shm/a2top/$$"
trace_opts="-t -e trace=network"

# get required vars for inactive requests display
case $ina_dis in
	0)	regex_string_ina=""; vregex_ina=0;;
	1)	regex_string_ina=" _ | \. "; vregex_ina=1;;
esac

while getopts "vhu:c:t:l:" OPTION; do
	case $OPTION in
		h)	echo -e "$version\n$cmd_help"; exit;;
		v)	echo "$version"; exit;;
		u)	status_url="$OPTARG";;
		c)	conf_file="$OPTARG";;
		t)	tmp="${OPTARG}/a2top/$$";;
		l)	trace_opts="${OPTARG}";
	esac
done

if [ -f "$conf_file" ]; then
	source $conf_file
	echo "Loaded settings from configuration file $conf_file"
else
	echo "Conifguration file $conf_file not found, using default values"
	#read -s -n 1
fi

if [ ! -d $tmp ]; then
	echo "Creating temporary directory $tmp"
	if ! mkdir -p $tmp; then
		echo " Directory creation failed"
	fi
else
	echo "Temporary directory already exist"
	exit
fi

echo "please wait ..."
tput smcup
#tput civis
trap terminate INT TERM EXIT
kill -winch $$
trap resize_window WINCH
recycle

while read -n 1 -s input; do
	exec 3>&2; exec 2> /dev/null;
	kill -9 $dis_pid
	case $input in 
		q|Q)	#trap terminate INT
			terminate;;
		p|P)	echo -n "PAUSED, hit any key to continue$(tput el)"; read -s -n 1; recycle;;
		#d|D)	echo -n "Refreshing window size"; kill -winch $$;;
		s|S)	pre_delay="$delay";
			read -p "Change delay from $delay to: $(tput el)" -e delay 2>&1; tput cuu1;
			if ! echo $delay | egrep "^[0-9.]+$" &>/dev/null; then
				echo -n " ${clre}Wrong input '$delay' for delay${clrr}$(tput el)"
				sleep 1
				delay=$pre_delay
			fi
			recycle;;
		c|C)	sb_dis=$((($sb_dis+1)%4)); echo -n "Scoreboard display mode $sb_dis$(tput el)"; recycle;;
		u|U)	uptime_dis=$((($uptime_dis+1)%3)); echo -n "Uptime display mode $uptime_dis$(tput el)"; recycle;;
		t)	pre_col_sort="$col_sort"
			read -p "Sort by (column name): $(tput el)" -e col_sort 2>&1; tput cuu1;
			if ! echo $col_sort | egrep "^(Srv|PID|Acc|M|CPU|SS|Req|Conn|Child|Slot|Client|VHost|Request)$" &>/dev/null; then
				echo -n " ${clre}Wrong input '$col_sort' for column${clrr}$(tput el)"
				sleep 1
				col_sort="$pre_col_sort"
			fi
			recycle;;
		T)	col_sort=''; echo -n "Column sort diabled$(tput el)"; recycle;;
		y)	echo -n "Reverse column sort$(tput el)"; col_sort_rev=$((($col_sort_rev+1)%2)); recycle;;
		r)	read -p "Grep inclusive regex: $(tput el)" -er regex_string 2>&1; vregex=0; recycle;;
		v)	read -p "Grep exclusive regex (-v): $(tput el)" -er regex_string 2>&1; vregex=1; recycle;;
		R)	echo -n "Grep disabled$(tput el)"; regex_string=""; vregex=0; recycle;;
		g)	read -p "Highlight regex: $(tput el)" -e hlight 2>&1; recycle;;
		i)	echo -n "Inactive display mode $ina_dis$(tput el)"
			ina_dis=$((($ina_dis+1)%2));
			case $ina_dis in
				0)	regex_string_ina=""; vregex_ina=0; recycle;;
				1)	regex_string_ina=" _ | \. "; vregex_ina=1; recycle;;
			esac;;
		o|O)	echo -n "Info display mode $info_dis$(tput el)"; info_dis=$((($info_dis+1)%2)); recycle;;
		l)	#trap - INT TERM EXIT
			read -p "PID to trace [$trace_opts]: $(tput el)" -e tracy 2>&1
			tracy_file="$tmp/trace_$tracy"
			echo strace $trace_opts -p $tracy -o $tracy_file & p="$!"
			read -n 1 -s
			strace $trace_opts -p $tracy -o $tracy_file & p="$!"
			less +F $tracy_file
			kill -9 $p; rm -f $tracy_file
			#trap terminate INT TERM EXIT
			#tput clear
			recycle;;
		A)	pre_a2_init_cmd="$a2_init_cmd"
			read -p "Apache init command [reload]: $(tput el)" -e a2_init_cmd 2>&1; tput cuu1;
			if ! echo $a2_init_cmd | egrep "^(|start|stop|restart|reload|force-reload|start-htcacheclean|stop-htcacheclean|status)$" &>/dev/null; then
				echo -n " ${clre}Wrong input '$a2_init_cmd' for /etc/init.d/apache2${clrr}$(tput el)"
				sleep 1
				a2_init_cmd="$pre_a2_init_cmd"
			else
				tput clear
				/etc/init.d/apache2 ${a2_init_cmd:=reload}
			fi
			recycle;;
		W)	echo -n "Saving Configuration to $conf_file$(tput el)"; save_conf; recycle;;
		d)	read -p "Tcpdump PID: $(tput el)" -e info_pid 2>&1; tput clear
			tput smam
			base_data="`lsof -p $info_pid -i -n -P | grep $info_pid | grep -v LISTEN`"
			dump_str="`echo \"$base_data\" | sed 's# (.*)#))#; s#.* #((host #; s#->#) and (host #; s#:# and tcp and port #g;' |\
				xargs | sed 's#) (#) or (#g'`"
			i=31
			color_str="`lsof -p $info_pid -i -n -P | grep $info_pid | grep -v LISTEN |\
				sed 's# (.*)##; s#.* ##; s#-># #; s#:#.#g' |\
				while read line; do
					i=$((++i))
					echo \"$line\" | awk -v COL=\"$i\" '{print "s#"$1"#\x1b[1m\x1b["COL"m"$1"\x1b[m\x1b(B#; s#"$2"#\x1b[1m\x1b["COL"m"$2"\x1b[m\x1b(B#g;"}'
				done`"
			echo "$base_data"
			echo "$base_data" | sed "$color_str" > $tmp/tcpdump
			echo; echo;
			tcpdump -n "$dump_str" 2>&1 | sed "$color_str" >> $tmp/tcpdump &
			dump_pid=$!
			trap - INT TERM EXIT
			less -r +F $tmp/tcpdump
			trap terminate INT TERM EXIT
			kill -9 $dump_pid
			rm $tmp/tcpdump
			tput rmam
			recycle;;
		f)	read -p "Info PID: $(tput el)" -e info_pid 2>&1; tput clear
			echo "lsof sockets
------------
`lsof -p $info_pid -i -n -P | grep $info_pid`"
			recycle;;
		k|K)	pre_kill_pid=$kill_pid; pre_kill_sig=$kill_sig;
			read -p "PID to kill (make sure you know what u r doing): $(tput el)" -e kill_pid 2>&1; tput cuu1;
			echo "$txtspace"; tput cuu1;
			if ! echo $kill_pid | egrep "^[0-9]+$" &>/dev/null; then
				echo -n " ${clre}Wrong input '$kill_pid' for kill pid${clrr}$(tput el)"
				sleep 1
				kill_pid=$pre_kill_pid
			elif ! cat /proc/$kill_pid/cmdline | egrep "apache|httpd" &>/dev/null; then
				echo -n " ${clre}Pid '$kill_pid' is not apache server (check /proc/$kill_pid/cmdline)${clrr}$(tput el)"
				sleep 1
				kill_pid=$pre_kill_pid
			else
				read -p " Kill pid $kill_pid with signal [15]: $(tput el)" -e kill_sig 2>&1; tput cuu1;
				echo "$txtspace"; tput cuu1;
				if ! echo $kill_sig | egrep "^[0-9]{1,2}$|^$" &>/dev/null; then
					echo -n " ${clre}Wrong input '$kill_sig' for kill signal${clrr}$(tput el)"
					kill_sig=""
					sleep 1
				else
					kill -${kill_sig:=15} $kill_pid
					echo -en " Killed pid $kill_pid with signal $kill_sig$(tput el)"
					sleep 1
				fi
			fi
			recycle;;
		h|H|\?)	tput clear
			echo -e "$help_screen" | less
			#echo -n "press any key to continue"
			#read -s -n 1
			recycle;;
		*)	echo -en "Unknown command, try ? or h$(tput el)\r "; recycle;;
	esac
	#trap terminate INT
	exec 2>&3; exec 3>&-;
done
